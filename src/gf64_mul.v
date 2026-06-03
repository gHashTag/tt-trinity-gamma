// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf64_mul.v
// GoldenFloat64 Multiplication Unit -- [S(1) | E(24) | M(39)], bias 2^(E-1)-1.
// value = (-1)^S (1 + M/2^39) 2^(E-bias).
//
// Rewritten 2026-06 (test/gen_gf_mul_fix.py). The previous version declared
// mant_product 2 bits too narrow (78 bits, not 80), truncating the leading
// bit of the (M+1)x(M+1) product, and bumped the exponent on rounding without
// incrementing the mantissa -- products came out ~half magnitude (1.0*1.0 -> 0.5).
// This version uses the verified gf16_mul/gf8_mul algorithm: full 80-bit product,
// normalize (prod[79] -> exp+1 else stay), mantissa = the 39 bits below the leading
// 1, round-to-nearest ties-to-zero (guard & (round | sticky)). Cross-checked by
// test/gf_arith_xcheck.py and test/gf_mul_sweep.py. Special-value encodings are
// preserved from the original unit (their conformance is a separate question).

`default_nettype none
module gf64_mul (
    input  wire [63:0] a,
    input  wire [63:0] b,
    output reg  [63:0] result
);

    localparam [23:0] EXP_MAX = 16777215;
    localparam signed [25:0] BIAS_S    = 26'sd8388607;
    localparam signed [25:0] EXP_MAX_S = 26'sd16777215;

    wire             sign_a = a[63];
    wire [23:0]   exp_a  = a[62:39];
    wire [38:0]   mant_a = a[38:0];
    wire             sign_b = b[63];
    wire [23:0]   exp_b  = b[62:39];
    wire [38:0]   mant_b = b[38:0];

    wire is_zero_a = (exp_a == 24'd0) && (mant_a == 39'd0);
    wire is_zero_b = (exp_b == 24'd0) && (mant_b == 39'd0);
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == 39'd0);
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == 39'd0);
    wire is_nan_a  = (exp_a == EXP_MAX) && (mant_a != 39'd0);
    wire is_nan_b  = (exp_b == EXP_MAX) && (mant_b != 39'd0);

    wire result_sign = sign_a ^ sign_b;

    wire [79:0] full_prod = {1'b1, mant_a} * {1'b1, mant_b};  // 80-bit

    reg signed [25:0] raw_exp, final_exp;
    reg [38:0] mant_out, final_mant;
    reg [39:0]  mant_rounded;            // M+1 bits, catches mantissa overflow
    reg           guard, round_b, sticky;

    always @(*) begin
        raw_exp = 0; final_exp = 0; mant_out = 0; final_mant = 0;
        mant_rounded = 0; guard = 0; round_b = 0; sticky = 0;

        if (is_nan_a || is_nan_b)
            result = 64'hFFFFFFFFFF801;
        else if (is_inf_a && is_zero_b)
            result = 64'hFFFFFFFFFF801;
        else if (is_inf_b && is_zero_a)
            result = 64'hFFFFFFFFFF801;
        else if (is_inf_a || is_inf_b)
            result = result_sign ? 64'hFFFFFFFFFF800 : 64'h7FFFFFFFF800;
        else if (is_zero_a || is_zero_b)
            result = 64'h0000000000000000;
        else begin
            raw_exp = $signed({2'b00, exp_a}) + $signed({2'b00, exp_b}) - BIAS_S;

            if (full_prod[79]) begin                 // product in [2,4) -> exp+1
                raw_exp  = raw_exp + 1;
                mant_out = full_prod[78:40];
                guard    = full_prod[39];
                round_b  = full_prod[38];
                sticky   = |full_prod[37:0];
            end else begin                              // product in [1,2)
                mant_out = full_prod[77:39];
                guard    = full_prod[38];
                round_b  = full_prod[37];
                sticky   = |full_prod[36:0];
            end

            if (guard && (round_b || sticky))
                mant_rounded = {1'b0, mant_out} + 1'b1;
            else
                mant_rounded = {1'b0, mant_out};

            if (mant_rounded[39]) begin               // mantissa overflow
                final_exp  = raw_exp + 1;
                final_mant = 0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded[38:0];
            end

            if (final_exp < 0)
                result = 64'h0000000000000000;                        // underflow
            else if (final_exp >= EXP_MAX_S)
                result = result_sign ? 64'hFFFFFFFFFF800 : 64'h7FFFFFFFF800;  // overflow
            else if (final_exp == 0 && final_mant == 39'd0)
                result = 64'h0000000000000000;                        // exp0/mant0 is the zero code
            else
                result = {result_sign, final_exp[23:0], final_mant};
        end
    end

endmodule
