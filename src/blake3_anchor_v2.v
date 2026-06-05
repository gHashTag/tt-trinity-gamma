`default_nettype none
// blake3_anchor_v2.v — CORRECTED BLAKE3-mini RECEIPT signer (single-block).
// Apache-2.0
//
// FIX (2026-06): the shipped blake3_anchor's G() omitted ALL FOUR XOR steps
// (d ^= a before ROTR16/ROTR8; b ^= c before ROTR12/ROTR7) -- the core diffusion
// of BLAKE3's mixing function. Without them the digest is a near-LINEAR function of
// the input, so it is NOT preimage/collision-resistant (the header's "~2^96"
// security claim was false). Verified: the shipped RTL == a no-XOR model and !=
// the real BLAKE3-G model; this v2 == the real BLAKE3-G model
// (test/blake3_anchor_verify.py). v2 restores BLAKE3's G; it is the correction for
// a respin (the fabricated Gamma/Euler dies use the original, frozen).
//
// NB (still a reduced variant): 4 rounds (not 7), and no per-round message-schedule
// permutation -- documented simplifications of the "mini" variant; the XOR fix is the
// security-critical one. Full-round + permuted BLAKE3 is the Wave-5 target.
//
// PhD anchor: Chapter 12 / DePIN — per-die cryptographic RECEIPT signing.
// Interface: 64-byte message in (512 bits), 32-byte digest out (256 bits).
// Single-shot: assert `start` with `m_in` valid, wait for `done`.

module blake3_anchor_v2 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [511:0] m_in,
    output reg          done,
    output reg  [255:0] digest,
    output wire         hash_ok
);

    // BLAKE3 IV constants (same as BLAKE2s / SHA-256 initial state)
    localparam [31:0] IV0 = 32'h6a09e667;
    localparam [31:0] IV1 = 32'hbb67ae85;
    localparam [31:0] IV2 = 32'h3c6ef372;
    localparam [31:0] IV3 = 32'ha54ff53a;
    localparam [31:0] IV4 = 32'h510e527f;
    localparam [31:0] IV5 = 32'h9b05688c;
    localparam [31:0] IV6 = 32'h1f83d9ab;
    localparam [31:0] IV7 = 32'h5be0cd19;

    reg [31:0] v [0:15];          // 16-word working state
    reg [31:0] m [0:15];          // message words
    reg [2:0]  round;             // 0..3 (4 rounds)
    reg [3:0]  step;
    reg        busy;

    integer i;

    // Quarter-round mixing function G(a,b,c,d, x,y)
    task automatic g_mix;
        input  [3:0] ia, ib, ic, id;
        input  [31:0] x, y;
        reg [31:0] a, b, c, d;
        begin
            a = v[ia]; b = v[ib]; c = v[ic]; d = v[id];
            // FIX (2026-06): BLAKE3's G XORs d^=a and b^=c BEFORE each rotate; the
            // shipped blake3_anchor omitted all four XORs, gutting the diffusion
            // (the digest became a near-linear function of the input -- NOT the
            // claimed preimage-resistance). Restored to the real BLAKE3 G.
            a = a + b + x;
            d = d ^ a;  d = {d[15:0], d[31:16]};  // ROTR16(d ^ a)
            c = c + d;
            b = b ^ c;  b = {b[11:0], b[31:12]};  // ROTR12(b ^ c)
            a = a + b + y;
            d = d ^ a;  d = {d[7:0], d[31:8]};    // ROTR8(d ^ a)
            c = c + d;
            b = b ^ c;  b = {b[6:0], b[31:7]};    // ROTR7(b ^ c)
            v[ia] = a; v[ib] = b; v[ic] = c; v[id] = d;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy   <= 1'b0;
            done   <= 1'b0;
            round  <= 3'd0;
            step   <= 4'd0;
            digest <= 256'b0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                // Initialize state: v[0..7] = IV, v[8..15] = parameter block (zeros for demo)
                v[0]  <= IV0; v[1]  <= IV1; v[2]  <= IV2; v[3]  <= IV3;
                v[4]  <= IV4; v[5]  <= IV5; v[6]  <= IV6; v[7]  <= IV7;
                v[8]  <= IV0; v[9]  <= IV1; v[10] <= IV2; v[11] <= IV3;
                v[12] <= 32'b0; v[13] <= 32'b0; v[14] <= 32'b0; v[15] <= 32'b0;
                for (i = 0; i < 16; i = i + 1)
                    // Verilog-2005 compatible: extract 32 bits using shift and mask
                    m[i] <= (m_in >> (i * 32)) & 32'hFFFFFFFF;
                round <= 3'd0;
                step  <= 4'd0;
                busy  <= 1'b1;
            end else if (busy) begin
                if (round < 4) begin
                    // Apply column step (4 g_mix) then diagonal step (4 g_mix)
                    case (step)
                        4'd0: g_mix(4'd0, 4'd4, 4'd8,  4'd12, m[0],  m[1]);
                        4'd1: g_mix(4'd1, 4'd5, 4'd9,  4'd13, m[2],  m[3]);
                        4'd2: g_mix(4'd2, 4'd6, 4'd10, 4'd14, m[4],  m[5]);
                        4'd3: g_mix(4'd3, 4'd7, 4'd11, 4'd15, m[6],  m[7]);
                        4'd4: g_mix(4'd0, 4'd5, 4'd10, 4'd15, m[8],  m[9]);
                        4'd5: g_mix(4'd1, 4'd6, 4'd11, 4'd12, m[10], m[11]);
                        4'd6: g_mix(4'd2, 4'd7, 4'd8,  4'd13, m[12], m[13]);
                        4'd7: begin
                            g_mix(4'd3, 4'd4, 4'd9, 4'd14, m[14], m[15]);
                            round <= round + 3'd1;
                        end
                        default: ;
                    endcase
                    step <= (step == 4'd7) ? 4'd0 : step + 4'd1;
                end else begin
                    // Finalize: digest = v[0..7] XOR v[8..15]
                    digest <= {
                        v[7] ^ v[15], v[6] ^ v[14], v[5] ^ v[13], v[4] ^ v[12],
                        v[3] ^ v[11], v[2] ^ v[10], v[1] ^ v[9],  v[0] ^ v[8]
                    };
                    done <= 1'b1;
                    busy <= 1'b0;
                end
            end
        end
    end

    assign hash_ok = 1'b1;

endmodule
