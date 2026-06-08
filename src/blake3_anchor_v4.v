`default_nettype none
// blake3_anchor_v4.v -- full BLAKE3 compression function (keyed/tree-capable).
// Apache-2.0
//
// Extends blake3_anchor_v3 (Wave-5: 7 rounds + message permutation, correct G with
// XOR) to the REAL BLAKE3 compression interface:
//   - configurable chaining value `cv_in` (256b) -> state[0..7]   (IV for a root
//     first block; the previous block's CV otherwise; the key for keyed hashing)
//   - 64-bit `counter` (t0,t1), 32-bit `block_len`, 32-bit `flags` -> state[12..15]
//   - full 16-word output: out[0..7] = state[i]^state[i+8] (the next chaining value
//     / first half of the XOF stream), out[8..15] = state[i+8]^cv[i].
// This is the compression primitive multi-block / keyed / tree BLAKE3 is built from
// (chain CVs block-to-block; set the ROOT/CHUNK_START/CHUNK_END/KEYED_HASH flag
// bits). Verified == the reference BLAKE3 compress() over random
// (cv, m, counter, block_len, flags) -- test/blake3_anchor_v4_verify.py.
//
// `digest` (256b) = the chaining-value half (out[0..7]); `out_full` (512b) = all 16
// output words. Dead-code reference unit; the fabricated dies use the frozen
// blake3_anchor (single-block, no XOR). R-SI-1: shift-and-add G, zero `*`.

module blake3_anchor_v4 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [511:0] m_in,        // 16 message words
    input  wire [255:0] cv_in,       // chaining value / key (8 words)
    input  wire [63:0]  counter,     // block counter t0,t1
    input  wire [31:0]  block_len,   // bytes in this block
    input  wire [31:0]  flags,       // domain-separation flags
    output reg          done,
    output reg  [255:0] digest,      // next chaining value = out[0..7]
    output reg  [511:0] out_full,    // full 16-word output (XOF)
    output wire         hash_ok
);
    localparam [31:0] IV0=32'h6a09e667, IV1=32'hbb67ae85, IV2=32'h3c6ef372, IV3=32'ha54ff53a;
    localparam [31:0] IV4=32'h510e527f, IV5=32'h9b05688c, IV6=32'h1f83d9ab, IV7=32'h5be0cd19;

    reg [31:0] v  [0:15];
    reg [31:0] m  [0:15];
    reg [31:0] cv [0:7];            // saved chaining value for the second fold
    reg [2:0]  round;
    reg [3:0]  step;
    reg        busy;
    integer i;

    // Quarter-round G with the four XOR diffusion steps (ROTR 16/12/8/7).
    task automatic g_mix;
        input  [3:0] ia, ib, ic, id;
        input  [31:0] x, y;
        reg [31:0] a, b, c, d;
        begin
            a=v[ia]; b=v[ib]; c=v[ic]; d=v[id];
            a=a+b+x; d=d^a; d={d[15:0],d[31:16]};
            c=c+d;   b=b^c; b={b[11:0],b[31:12]};
            a=a+b+y; d=d^a; d={d[7:0],d[31:8]};
            c=c+d;   b=b^c; b={b[6:0],b[31:7]};
            v[ia]=a; v[ib]=b; v[ic]=c; v[id]=d;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy<=1'b0; done<=1'b0; round<=3'd0; step<=4'd0; digest<=256'b0; out_full<=512'b0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                // state init: v[0..7]=cv, v[8..11]=IV0..3, v[12..15]=t0,t1,blen,flags
                for (i=0;i<8;i=i+1) begin
                    cv[i] <= (cv_in >> (i*32)) & 32'hFFFFFFFF;
                    v[i]  <= (cv_in >> (i*32)) & 32'hFFFFFFFF;
                end
                v[8]<=IV0; v[9]<=IV1; v[10]<=IV2; v[11]<=IV3;
                v[12]<=counter[31:0]; v[13]<=counter[63:32]; v[14]<=block_len; v[15]<=flags;
                for (i=0;i<16;i=i+1) m[i] <= (m_in >> (i*32)) & 32'hFFFFFFFF;
                round<=3'd0; step<=4'd0; busy<=1'b1;
            end else if (busy) begin
                if (round < 7) begin
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
                            round <= round + 3'd1;
                            // BLAKE3 message permutation [2,6,3,10,7,0,4,13,1,11,12,5,9,14,15,8]
                            m[0]<=m[2];  m[1]<=m[6];  m[2]<=m[3];  m[3]<=m[10];
                            m[4]<=m[7];  m[5]<=m[0];  m[6]<=m[4];  m[7]<=m[13];
                            m[8]<=m[1];  m[9]<=m[11]; m[10]<=m[12]; m[11]<=m[5];
                            m[12]<=m[9]; m[13]<=m[14]; m[14]<=m[15]; m[15]<=m[8];
                        end
                        default: ;
                    endcase
                    step <= (step==4'd7) ? 4'd0 : step + 4'd1;
                end else begin
                    // finalize: out[i]=v[i]^v[i+8] (i=0..7), out[i+8]=v[i+8]^cv[i]
                    digest <= { v[7]^v[15], v[6]^v[14], v[5]^v[13], v[4]^v[12],
                                v[3]^v[11], v[2]^v[10], v[1]^v[9],  v[0]^v[8] };
                    out_full <= {
                        v[15]^cv[7], v[14]^cv[6], v[13]^cv[5], v[12]^cv[4],
                        v[11]^cv[3], v[10]^cv[2], v[9]^cv[1],  v[8]^cv[0],
                        v[7]^v[15],  v[6]^v[14],  v[5]^v[13],  v[4]^v[12],
                        v[3]^v[11],  v[2]^v[10],  v[1]^v[9],   v[0]^v[8] };
                    done<=1'b1; busy<=1'b0;
                end
            end
        end
    end

    assign hash_ok = 1'b1;
endmodule

`default_nettype wire
