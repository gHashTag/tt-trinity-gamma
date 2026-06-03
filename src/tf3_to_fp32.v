// SPDX-License-Identifier: Apache-2.0
// tt-trinity-gamma/src/tf3_to_fp32.v
// TF3 (Ternary Float 3, 8-bit ternary-weight container) -> IEEE-754 FP32.
//
// Layout (t27/specs/numeric/tf3.t27): [S(1) E(3) M(4)] = [7][6:4][3:0], bias 3.
// Canonical decode (tf3_to_f32 in the spec):
//     value = (-1)^S * (1 + M/16) * 2^(E-3)
//   specials:  0x00 -> +0, 0x80 -> -0
//              E==7, M==0 -> +/-Inf   (true encoding 0x70 / 0xF0)
//              E==7, M!=0 -> NaN
// NB: the spec's named constants TF3_INF_POS=0x78 / TF3_INF_NEG=0xF8 are
// INCONSISTENT with their own "exp=7, mant=0" definition -- 0x78 = 0111_1000 is
// exp=7, mant=8 (a NaN). This RTL follows the bit LAYOUT (exp==7 && mant==0 =>
// Inf), so true Inf is 0x70/0xF0 and 0x78/0xF8 decode to NaN. [Open conjecture]
// on the spec constants; the layout decode is self-consistent.
//   NB: E==0 is NOT subnormal here -- the formula applies for all E in 0..6.
//
// Honesty note (claim-status discipline): the spec's `mant_lookup_table` and its
// `tf3_from_f32` encoder are each internally INCONSISTENT with this `tf3_to_f32`
// formula (the table renders 0x3C00=1.0 for e=0,m=0 where the formula gives
// 2^-3=0.125; the encoder's (scaled-0.5)*16 mantissa is not the inverse of
// 1+M/16). The reference Zig functions use the FORMULA, which is self-consistent
// and is the conformance-relevant direction for the Corona oracle -- so this RTL
// implements the formula and does NOT bake the inconsistent encoder into silicon.
// Status: [Spec] (decode exhaustively cross-checked, 256/256, in the testbench).

`default_nettype none

module tf3_to_fp32 (
    input  wire [7:0]  tf3_in,
    output reg  [31:0] fp_out
);
    wire       sign = tf3_in[7];
    wire [2:0] exp  = tf3_in[6:4];
    wire [3:0] mant = tf3_in[3:0];

    // FP32 exponent for a normal TF3 value: (E - 3) + 127 = E + 124.
    wire [7:0] fp_exp = {5'd0, exp} + 8'd124;

    always @(*) begin
        if (exp == 3'd0 && mant == 4'd0)
            fp_out = {sign, 8'd0, 23'd0};            // +/-0
        else if (exp == 3'd7 && mant == 4'd0)
            fp_out = {sign, 8'hFF, 23'd0};           // +/-Inf
        else if (exp == 3'd7)
            fp_out = {sign, 8'hFF, 23'h400000};      // NaN (quiet)
        else
            // (1 + M/16) * 2^(E-3): M occupies the top 4 FP32 mantissa bits.
            fp_out = {sign, fp_exp, mant, 19'd0};
    end
endmodule
