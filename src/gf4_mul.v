// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf4_mul.v
// GoldenFloat4 Multiplication Unit
// Layout: [S(1) | E(1) | M(2)] - BIAS = 0
//
// GF4 is degenerate (see gf4_add.v): finite values are {+-1.25,+-1.5,+-1.75}
// (significand 4+mant in quarter units, all sharing exponent 2^0). The previous
// unit did `result = {sign, exp_a^exp_b, mant_a+mant_b}`, which is not a float
// multiply at all, and its is_inf test used EXP_MAX[0]==0 (aliasing Inf to zero).
// Rewritten 2026-06: multiply the significands exactly (in 1/16 units) and round
// to nearest of {0,1.25,1.5,1.75,Inf}. Only 1.25*1.25=1.5625 stays finite (->1.5);
// every other finite product exceeds 1.875 and overflows to Inf. Verified
// exhaustively (256/256 pairs) by test/gf4_exhaustive.py.
// Encodings: +0=0x0 -0=0x8 +Inf=0x4 -Inf=0xC NaN=0xE; 1.25/1.5/1.75 = m=1/2/3.

`default_nettype none
module gf4_mul (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output reg  [3:0] result
);

    wire        sign_a = a[3];
    wire        exp_a  = a[2];
    wire [1:0]  mant_a = a[1:0];
    wire        sign_b = b[3];
    wire        exp_b  = b[2];
    wire [1:0]  mant_b = b[1:0];

    wire is_zero_a = (exp_a == 1'b0) && (mant_a == 2'd0);
    wire is_zero_b = (exp_b == 1'b0) && (mant_b == 2'd0);
    wire is_inf_a  = (exp_a == 1'b1) && (mant_a == 2'd0);
    wire is_inf_b  = (exp_b == 1'b1) && (mant_b == 2'd0);
    wire is_nan_a  = (exp_a == 1'b1) && (mant_a != 2'd0);
    wire is_nan_b  = (exp_b == 1'b1) && (mant_b != 2'd0);

    wire result_sign = sign_a ^ sign_b;

    reg [5:0] prod;        // (4+mant_a)*(4+mant_b) in 1/16 units, 16..49

    always @(*) begin
        prod = 0;
        if (is_nan_a || is_nan_b)
            result = 4'hE;
        else if ((is_inf_a && is_zero_b) || (is_inf_b && is_zero_a))
            result = 4'hE;                                  // 0 * Inf = NaN
        else if (is_inf_a || is_inf_b)
            result = result_sign ? 4'hC : 4'h4;
        else if (is_zero_a || is_zero_b)
            result = result_sign ? 4'h8 : 4'h0;
        else begin
            prod = {1'b1, mant_a} * {1'b1, mant_b};         // 1/16 units
            // round to nearest grid point {0,20,24,28} sixteenths; >=30 -> Inf
            if (prod < 6'd10)
                result = result_sign ? 4'h8 : 4'h0;         // -> 0
            else if (prod < 6'd22)
                result = {result_sign, 1'b0, 2'b01};        // 1.25
            else if (prod < 6'd26)
                result = {result_sign, 1'b0, 2'b10};        // 1.5
            else if (prod < 6'd30)
                result = {result_sign, 1'b0, 2'b11};        // 1.75
            else
                result = result_sign ? 4'hC : 4'h4;         // overflow -> Inf
        end
    end

endmodule
