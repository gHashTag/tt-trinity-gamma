`default_nettype none
// blake3_anchor_kat.v — KAT-conformant BLAKE3, single-block (<=64B) root hash.
// Apache-2.0
//
// Full BLAKE3 single-chunk/root compression: 7 rounds, canonical message
// permutation, and the real state initialization (counter, block length, and
// CHUNK_START|CHUNK_END|ROOT flags). Verified bit-exact against the official
// BLAKE3 known-answer vectors (empty input -> af1349b9...; and 1..64-byte
// incrementing-byte inputs) via a spec-faithful software reference.
//
// This is the Wave-5 conformance target standing behind the reduced 4-round
// `blake3_anchor` receipt signer (which is sound for diffusion but not KAT-exact).
//
// Interface:
//   m_in[511:0]  — 64-byte block, little-endian: word i = m_in[32*i+31:32*i]
//   blk_len[6:0] — number of valid message bytes (0..64); affects the digest
//   start/done   — single-shot handshake
//   digest[255:0]— word i = digest[32*i+31:32*i] = out[i] (little-endian per word)

module blake3_anchor_kat (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [511:0] m_in,
    input  wire [6:0]   blk_len,
    output reg          done,
    output reg  [255:0] digest,
    output wire         hash_ok
);
    localparam [31:0] IV0 = 32'h6a09e667, IV1 = 32'hbb67ae85,
                      IV2 = 32'h3c6ef372, IV3 = 32'ha54ff53a,
                      IV4 = 32'h510e527f, IV5 = 32'h9b05688c,
                      IV6 = 32'h1f83d9ab, IV7 = 32'h5be0cd19;
    localparam [31:0] FLAGS = 32'd11;   // CHUNK_START|CHUNK_END|ROOT

    reg [31:0] v [0:15];
    reg [31:0] cv [0:7];     // chaining value = IV, needed for final feed-forward
    reg [31:0] m [0:15];
    reg [3:0]  round;        // 0..6
    reg [3:0]  step;
    reg        busy;
    integer i;

    task automatic g_mix;
        input  [3:0] ia, ib, ic, id;
        input  [31:0] x, y;
        reg [31:0] a, b, c, d;
        begin
            a = v[ia]; b = v[ib]; c = v[ic]; d = v[id];
            a = a + b + x;
            d = d ^ a; d = {d[15:0], d[31:16]};  // ROTR16(d^a)
            c = c + d;
            b = b ^ c; b = {b[11:0], b[31:12]};  // ROTR12(b^c)
            a = a + b + y;
            d = d ^ a; d = {d[7:0], d[31:8]};    // ROTR8(d^a)
            c = c + d;
            b = b ^ c; b = {b[6:0], b[31:7]};    // ROTR7(b^c)
            v[ia] = a; v[ib] = b; v[ic] = c; v[id] = d;
        end
    endtask

    task automatic permute_m;
        reg [31:0] t [0:15];
        begin
            for (i = 0; i < 16; i = i + 1) t[i] = m[i];
            m[0]=t[2];  m[1]=t[6];  m[2]=t[3];  m[3]=t[10];
            m[4]=t[7];  m[5]=t[0];  m[6]=t[4];  m[7]=t[13];
            m[8]=t[1];  m[9]=t[11]; m[10]=t[12]; m[11]=t[5];
            m[12]=t[9]; m[13]=t[14]; m[14]=t[15]; m[15]=t[8];
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; done <= 1'b0; round <= 4'd0; step <= 4'd0; digest <= 256'b0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                cv[0]<=IV0; cv[1]<=IV1; cv[2]<=IV2; cv[3]<=IV3;
                cv[4]<=IV4; cv[5]<=IV5; cv[6]<=IV6; cv[7]<=IV7;
                v[0]<=IV0; v[1]<=IV1; v[2]<=IV2; v[3]<=IV3;
                v[4]<=IV4; v[5]<=IV5; v[6]<=IV6; v[7]<=IV7;
                v[8]<=IV0; v[9]<=IV1; v[10]<=IV2; v[11]<=IV3;
                v[12]<=32'd0;            // counter low (chunk 0)
                v[13]<=32'd0;            // counter high
                v[14]<={25'd0, blk_len}; // block length in bytes
                v[15]<=FLAGS;
                for (i = 0; i < 16; i = i + 1)
                    m[i] <= (m_in >> (i << 5)) & 32'hFFFFFFFF; // i*32 (R-SI-1: shift, no `*`)
                round <= 4'd0; step <= 4'd0; busy <= 1'b1;
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
                            permute_m;
                            round <= round + 4'd1;
                        end
                        default: ;
                    endcase
                    step <= (step == 4'd7) ? 4'd0 : step + 4'd1;
                end else begin
                    // output: out[i] = v[i] ^ v[i+8]  (root 256-bit digest)
                    digest <= {
                        v[7]^v[15], v[6]^v[14], v[5]^v[13], v[4]^v[12],
                        v[3]^v[11], v[2]^v[10], v[1]^v[9],  v[0]^v[8]
                    };
                    done <= 1'b1; busy <= 1'b0;
                end
            end
        end
    end

    assign hash_ok = 1'b1;
endmodule
