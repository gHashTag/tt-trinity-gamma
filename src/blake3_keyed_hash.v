`default_nettype none
// blake3_keyed_hash.v -- keyed BLAKE3 (MAC), multi-chunk tree, <=4096 bytes.
// Apache-2.0
//
// Keyed variant of blake3_hash: the 256-bit key replaces the IV as the initial
// chaining value for every chunk-start and parent node, and the KEYED_HASH flag
// (16) is OR'd into every compression. Everything else (7-round+perm core, chunk
// stack, ROOT-on-final-parent) is identical. This is the DePIN receipt MAC: a
// per-die key authenticates the RECEIPT. Verified == blake3.blake3(data, key=key)
// over all lengths 0..4096 (test/blake3_keyed_hash_verify.py). Dead-code reference.
module blake3_keyed_hash (
    input  wire           clk,
    input  wire           rst_n,
    input  wire           start,
    input  wire [32767:0] msg,        // up to 4096 bytes, zero-padded beyond msg_len
    input  wire [12:0]    msg_len,    // 0..4096
    input  wire [255:0]   key_in,     // 32-byte key (8 words, LE)
    output reg            done,
    output reg  [255:0]   hash,
    output wire           hash_ok
);
    localparam [31:0] IV0=32'h6a09e667,IV1=32'hbb67ae85,IV2=32'h3c6ef372,IV3=32'ha54ff53a;
    localparam [31:0] IV4=32'h510e527f,IV5=32'h9b05688c,IV6=32'h1f83d9ab,IV7=32'h5be0cd19;
    localparam [31:0] F_CS=32'd1, F_CE=32'd2, F_PA=32'd4, F_RT=32'd8, F_KH=32'd16;
    localparam [3:0] IDLE=0,CHUNK_POST=2,CHUNK_FIN=3,MERGE=4,PAR_POST=6,FINI=7;

    reg [31:0] v [0:15];
    reg [31:0] m [0:15];
    reg [31:0] res[0:7];
    reg [31:0] key[0:7];
    reg [2:0]  round; reg [3:0] step; reg eng_run; reg [3:0] ret_phase;
    reg [3:0]  phase;
    reg [2:0]  nchunks, chunk_i;
    reg [4:0]  cblk, cnblk;
    reg [31:0] stack[0:1][0:7];
    reg [1:0]  sp;
    reg [31:0] seed[0:7];
    reg [2:0]  merge_tot;
    reg        merging_final;
    integer i,j;
    reg [15:0] cbase;

    function [31:0] ivw; input [2:0] k; begin
        ivw=(k==0)?IV0:(k==1)?IV1:(k==2)?IV2:(k==3)?IV3:(k==4)?IV4:(k==5)?IV5:(k==6)?IV6:IV7;
    end endfunction
    function [12:0] clen_of; input [2:0] ci; reg [12:0] cb; begin
        cb={ci,10'd0};
        clen_of=(msg_len<=cb)?13'd0:((msg_len-cb>=13'd1024)?13'd1024:(msg_len-cb)); end endfunction
    function [4:0] nblk_of; input [2:0] ci; reg [12:0] cl; begin
        cl=clen_of(ci); nblk_of=(cl==0)?5'd1:((cl+13'd63)>>6); end endfunction
    function [31:0] blen_of; input [2:0] ci; input [4:0] bk; reg [12:0] off; begin
        off={ci,10'd0}+{bk,6'd0};
        blen_of=(off>=msg_len)?32'd0:((msg_len-off>=13'd64)?32'd64:{19'd0,(msg_len-off)}); end endfunction
    function [31:0] cflags; input [2:0] ci; input [4:0] bk; reg [31:0] f; begin
        f=F_KH | ((bk==5'd0)?F_CS:32'd0);
        if (bk==nblk_of(ci)-5'd1) f=f|F_CE|((nchunks==3'd1)?F_RT:32'd0);
        cflags=f; end endfunction

    task automatic g_mix; input [3:0] ia,ib,ic,id; input [31:0] x,y; reg [31:0] a,b,c,d; begin
        a=v[ia];b=v[ib];c=v[ic];d=v[id];
        a=a+b+x; d=d^a; d={d[15:0],d[31:16]};
        c=c+d;   b=b^c; b={b[11:0],b[31:12]};
        a=a+b+y; d=d^a; d={d[7:0],d[31:8]};
        c=c+d;   b=b^c; b={b[6:0],b[31:7]};
        v[ia]=a;v[ib]=b;v[ic]=c;v[id]=d;
    end endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin phase<=IDLE; done<=1'b0; eng_run<=1'b0; sp<=2'd0; hash<=256'b0; end
        else begin
            done<=1'b0;
            if (eng_run) begin
                case (step)
                    4'd0: g_mix(4'd0,4'd4,4'd8, 4'd12, m[0], m[1]);
                    4'd1: g_mix(4'd1,4'd5,4'd9, 4'd13, m[2], m[3]);
                    4'd2: g_mix(4'd2,4'd6,4'd10,4'd14, m[4], m[5]);
                    4'd3: g_mix(4'd3,4'd7,4'd11,4'd15, m[6], m[7]);
                    4'd4: g_mix(4'd0,4'd5,4'd10,4'd15, m[8], m[9]);
                    4'd5: g_mix(4'd1,4'd6,4'd11,4'd12, m[10],m[11]);
                    4'd6: g_mix(4'd2,4'd7,4'd8, 4'd13, m[12],m[13]);
                    4'd7: begin
                        g_mix(4'd3,4'd4,4'd9,4'd14, m[14],m[15]);
                        if (round<3'd6) begin
                            round<=round+3'd1;
                            m[0]<=m[2];m[1]<=m[6];m[2]<=m[3];m[3]<=m[10];m[4]<=m[7];m[5]<=m[0];
                            m[6]<=m[4];m[7]<=m[13];m[8]<=m[1];m[9]<=m[11];m[10]<=m[12];m[11]<=m[5];
                            m[12]<=m[9];m[13]<=m[14];m[14]<=m[15];m[15]<=m[8];
                        end else begin
                            for (i=0;i<8;i=i+1) res[i]<=v[i]^v[i+8];
                            eng_run<=1'b0; phase<=ret_phase;
                        end
                    end
                    default: ;
                endcase
                step<=(step==4'd7)?4'd0:step+4'd1;
            end else begin
              case (phase)
                IDLE: if (start) begin
                    nchunks<=(msg_len==13'd0)?3'd1:((msg_len+13'd1023)>>10);
                    chunk_i<=3'd0; cblk<=5'd0; sp<=2'd0; cnblk<=nblk_of(3'd0);
                    for (j=0;j<16;j=j+1) m[j] <= msg[j*32 +: 32];
                    for (j=0;j<8;j=j+1) key[j] <= key_in[j*32 +: 32];
                    v[0]<=key_in[0+:32];v[1]<=key_in[32+:32];v[2]<=key_in[64+:32];v[3]<=key_in[96+:32];
                    v[4]<=key_in[128+:32];v[5]<=key_in[160+:32];v[6]<=key_in[192+:32];v[7]<=key_in[224+:32];
                    v[8]<=IV0;v[9]<=IV1;v[10]<=IV2;v[11]<=IV3;
                    v[12]<=32'd0;v[13]<=32'd0;v[14]<=blen_of(3'd0,5'd0);
                    // ROOT depends on single-chunk; derive from msg_len (nchunks is NBA-pending this cycle)
                    v[15]<= F_KH | F_CS | ((nblk_of(3'd0)==5'd1) ?
                            (F_CE | ((((msg_len+13'd1023)>>10)<=13'd1)?F_RT:32'd0)) : 32'd0);
                    round<=3'd0; step<=4'd0; eng_run<=1'b1; ret_phase<=CHUNK_POST;
                end
                CHUNK_POST: begin
                    if (cblk < cnblk-5'd1) begin
                        cblk<=cblk+5'd1; cbase = {chunk_i,13'd0} + {(cblk+5'd1),9'd0};
                        for (j=0;j<16;j=j+1) m[j] <= msg[cbase + j*32 +: 32];
                        for (j=0;j<8;j=j+1)  v[j] <= res[j];
                        v[8]<=IV0;v[9]<=IV1;v[10]<=IV2;v[11]<=IV3;
                        v[12]<={29'd0,chunk_i};v[13]<=32'd0;
                        v[14]<=blen_of(chunk_i,cblk+5'd1); v[15]<=cflags(chunk_i,cblk+5'd1);
                        round<=3'd0;step<=4'd0;eng_run<=1'b1;ret_phase<=CHUNK_POST;
                    end else begin
                        for (j=0;j<8;j=j+1) seed[j]<=res[j];
                        phase<=CHUNK_FIN;
                    end
                end
                CHUNK_FIN: begin
                    if (nchunks==3'd1) begin
                        hash<={seed[7],seed[6],seed[5],seed[4],seed[3],seed[2],seed[1],seed[0]};
                        phase<=FINI;
                    end else if (chunk_i < nchunks-3'd1) begin
                        merge_tot<=chunk_i+3'd1; merging_final<=1'b0; phase<=MERGE;
                    end else begin
                        merging_final<=1'b1; phase<=MERGE;
                    end
                end
                MERGE: begin
                    if (merging_final) begin
                        if (sp>2'd0) begin
                            for (j=0;j<8;j=j+1) begin m[j]<=stack[sp-2'd1][j]; m[j+8]<=seed[j]; end
                            for (j=0;j<8;j=j+1) v[j]<=key[j];
                            v[8]<=IV0;v[9]<=IV1;v[10]<=IV2;v[11]<=IV3;
                            v[12]<=32'd0;v[13]<=32'd0;v[14]<=32'd64;
                            v[15]<= F_KH | F_PA | ((sp==2'd1)?F_RT:32'd0);
                            sp<=sp-2'd1; round<=3'd0;step<=4'd0;eng_run<=1'b1;ret_phase<=PAR_POST;
                        end else begin
                            hash<={seed[7],seed[6],seed[5],seed[4],seed[3],seed[2],seed[1],seed[0]};
                            phase<=FINI;
                        end
                    end else begin
                        if (merge_tot[0]==1'b0 && sp>2'd0) begin
                            merge_tot<=merge_tot>>1;
                            for (j=0;j<8;j=j+1) begin m[j]<=stack[sp-2'd1][j]; m[j+8]<=seed[j]; end
                            for (j=0;j<8;j=j+1) v[j]<=key[j];
                            v[8]<=IV0;v[9]<=IV1;v[10]<=IV2;v[11]<=IV3;
                            v[12]<=32'd0;v[13]<=32'd0;v[14]<=32'd64;v[15]<=F_KH|F_PA;
                            sp<=sp-2'd1; round<=3'd0;step<=4'd0;eng_run<=1'b1;ret_phase<=PAR_POST;
                        end else begin
                            for (j=0;j<8;j=j+1) stack[sp][j]<=seed[j];
                            sp<=sp+2'd1;
                            chunk_i<=chunk_i+3'd1; cblk<=5'd0; cnblk<=nblk_of(chunk_i+3'd1);
                            cbase = {(chunk_i+3'd1),13'd0};
                            for (j=0;j<16;j=j+1) m[j] <= msg[cbase + j*32 +: 32];
                            for (j=0;j<8;j=j+1)  v[j] <= key[j];
                            v[8]<=IV0;v[9]<=IV1;v[10]<=IV2;v[11]<=IV3;
                            v[12]<={29'd0,(chunk_i+3'd1)};v[13]<=32'd0;
                            v[14]<=blen_of(chunk_i+3'd1,5'd0); v[15]<=cflags(chunk_i+3'd1,5'd0);
                            round<=3'd0;step<=4'd0;eng_run<=1'b1;ret_phase<=CHUNK_POST;
                        end
                    end
                end
                PAR_POST: begin for (j=0;j<8;j=j+1) seed[j]<=res[j]; phase<=MERGE; end
                FINI: begin done<=1'b1; phase<=IDLE; end
                default: phase<=IDLE;
              endcase
            end
        end
    end
    assign hash_ok = 1'b1;
endmodule

`default_nettype wire
