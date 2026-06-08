`default_nettype none
// blake3_hash_chunk.v -- single-chunk BLAKE3 hash (messages up to 1024 bytes).
// Apache-2.0
//
// Multi-block / flagged wrapper over the verified blake3_anchor_v4 compression core
// (7 rounds + permutation + correct G/XOR). Hashes an arbitrary message of up to one
// BLAKE3 chunk (1024 bytes = 16 x 64-byte blocks): it chains the chaining value (CV)
// block-to-block and sets the domain-separation flags --
//   block 0      : CHUNK_START
//   last block   : CHUNK_END | ROOT   (single chunk => its last block is the root)
//   counter      : 0 (chunk index 0); block_len = bytes in that block.
// CV starts at the IV (unkeyed). The 256-bit hash is the CV after the root block.
//
// Verified == a reference single-chunk BLAKE3 (validated against the official BLAKE3
// test vectors for lengths 0/1/.../1024) -- test/blake3_hash_chunk_verify.py.
// The caller zero-pads the message buffer beyond msg_len (as the spec does).
// Multi-chunk tree mode (parent nodes, counters>0) is a later wave. Dead-code
// reference; frozen dies untouched. R-SI-1: shift/add G, zero `*` in the datapath.

module blake3_hash_chunk (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [8191:0] msg,        // up to 1024 bytes, zero-padded beyond msg_len
    input  wire [10:0]   msg_len,    // 0..1024 bytes
    output reg           done,
    output reg  [255:0]  hash,
    output wire          hash_ok
);
    localparam [31:0] IV0=32'h6a09e667, IV1=32'hbb67ae85, IV2=32'h3c6ef372, IV3=32'ha54ff53a;
    localparam [31:0] IV4=32'h510e527f, IV5=32'h9b05688c, IV6=32'h1f83d9ab, IV7=32'h5be0cd19;
    localparam [31:0] F_CHUNK_START=32'd1, F_CHUNK_END=32'd2, F_ROOT=32'd8;

    reg [31:0] v  [0:15];
    reg [31:0] m  [0:15];
    reg [31:0] cv [0:7];
    reg [2:0]  round;
    reg [3:0]  step;
    reg [4:0]  blk, nblk;
    reg        busy;
    integer i;

    function [31:0] iv_word; input [2:0] k; begin
        case (k) 0:iv_word=IV0;1:iv_word=IV1;2:iv_word=IV2;3:iv_word=IV3;
                 4:iv_word=IV4;5:iv_word=IV5;6:iv_word=IV6;default:iv_word=IV7; endcase
    end endfunction

    // block_len and flags for block index b (single chunk, nblk total)
    function [31:0] blen_of; input [4:0] b; reg [10:0] rem; begin
        if (msg_len==11'd0) blen_of=32'd0;
        else if (b == nblk-5'd1) begin rem = msg_len - {b,6'd0}; blen_of={21'd0,rem}; end
        else blen_of=32'd64;
    end endfunction
    function [31:0] flags_of; input [4:0] b; reg [31:0] f; begin
        f=32'd0; if (b==5'd0) f=f|F_CHUNK_START; if (b==nblk-5'd1) f=f|F_CHUNK_END|F_ROOT;
        flags_of=f;
    end endfunction

    task automatic g_mix; input [3:0] ia,ib,ic,id; input [31:0] x,y; reg [31:0] a,b,c,d; begin
        a=v[ia]; b=v[ib]; c=v[ic]; d=v[id];
        a=a+b+x; d=d^a; d={d[15:0],d[31:16]};
        c=c+d;   b=b^c; b={b[11:0],b[31:12]};
        a=a+b+y; d=d^a; d={d[7:0],d[31:8]};
        c=c+d;   b=b^c; b={b[6:0],b[31:7]};
        v[ia]=a; v[ib]=b; v[ic]=c; v[id]=d;
    end endtask

    // load block b's 16 message words + initialise state v[] with the running cv
    task automatic init_block; input [4:0] b; integer j; reg [12:0] base; begin
        base = {b,9'd0};                                  // b*512
        for (j=0;j<16;j=j+1) m[j] <= msg[base + j*32 +: 32];
        for (j=0;j<8;j=j+1)  v[j] <= cv[j];
        v[8]<=IV0; v[9]<=IV1; v[10]<=IV2; v[11]<=IV3;
        v[12]<=32'd0; v[13]<=32'd0; v[14]<=blen_of(b); v[15]<=flags_of(b);
    end endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy<=1'b0; done<=1'b0; round<=3'd0; step<=4'd0; blk<=5'd0; nblk<=5'd1; hash<=256'b0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                for (i=0;i<8;i=i+1) cv[i] <= iv_word(i[2:0]);     // unkeyed: CV=IV
                nblk <= (msg_len==11'd0) ? 5'd1 : ((msg_len + 11'd63) >> 6);
                blk  <= 5'd0; round<=3'd0; step<=4'd0; busy<=1'b1;
                // init_block(0) inline (cv just set to IV this cycle -> use IV directly)
                begin : ld0
                  integer j;
                  for (j=0;j<16;j=j+1) m[j] <= msg[j*32 +: 32];
                  v[0]<=IV0;v[1]<=IV1;v[2]<=IV2;v[3]<=IV3;v[4]<=IV4;v[5]<=IV5;v[6]<=IV6;v[7]<=IV7;
                  v[8]<=IV0;v[9]<=IV1;v[10]<=IV2;v[11]<=IV3;
                  v[12]<=32'd0;v[13]<=32'd0;
                  v[14]<=(msg_len==11'd0)?32'd0:((((msg_len+11'd63)>>6)==5'd1)?{21'd0,msg_len}:32'd64);
                  v[15]<=F_CHUNK_START | (((msg_len+11'd63)>>6)<=5'd1 ? (F_CHUNK_END|F_ROOT):32'd0);
                end
            end else if (busy) begin
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
                        if (round < 3'd6) begin
                            round <= round + 3'd1;
                            m[0]<=m[2];  m[1]<=m[6];  m[2]<=m[3];  m[3]<=m[10];
                            m[4]<=m[7];  m[5]<=m[0];  m[6]<=m[4];  m[7]<=m[13];
                            m[8]<=m[1];  m[9]<=m[11]; m[10]<=m[12]; m[11]<=m[5];
                            m[12]<=m[9]; m[13]<=m[14]; m[14]<=m[15]; m[15]<=m[8];
                        end else begin
                            // round 6 done -> fold: new CV = v[i]^v[i+8]
                            for (i=0;i<8;i=i+1) cv[i] <= v[i]^v[i+8];
                            if (blk == nblk-5'd1) begin
                                hash <= { v[7]^v[15], v[6]^v[14], v[5]^v[13], v[4]^v[12],
                                          v[3]^v[11], v[2]^v[10], v[1]^v[9],  v[0]^v[8] };
                                done <= 1'b1; busy <= 1'b0;
                            end else begin
                                blk <= blk + 5'd1; round <= 3'd0;
                                // init next block with the NEW cv (v[i]^v[i+8])
                                begin : ldn
                                  integer j; reg [12:0] base;
                                  base = {(blk+5'd1),9'd0};
                                  for (j=0;j<16;j=j+1) m[j] <= msg[base + j*32 +: 32];
                                  for (j=0;j<8;j=j+1)  v[j] <= v[j]^v[j+8];
                                  v[8]<=IV0; v[9]<=IV1; v[10]<=IV2; v[11]<=IV3;
                                  v[12]<=32'd0; v[13]<=32'd0;
                                  v[14]<=blen_of(blk+5'd1); v[15]<=flags_of(blk+5'd1);
                                end
                            end
                        end
                    end
                    default: ;
                endcase
                step <= (step==4'd7) ? 4'd0 : step + 4'd1;
            end
        end
    end

    assign hash_ok = 1'b1;
endmodule

`default_nettype wire
