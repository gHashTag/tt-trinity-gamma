// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf32_mul.v
// GoldenFloat32 Multiplication Unit -- [S(1) | E(12) | M(19)], bias 2^(E-1)-1.
// value = (-1)^S (1 + M/2^19) 2^(E-bias).
//
// Rewritten 2026-06 (test/gen_gf_mul_fix.py). The previous version declared
// mant_product 2 bits too narrow (38 bits, not 40), truncating the leading
// bit of the (M+1)x(M+1) product, and bumped the exponent on rounding without
// incrementing the mantissa -- products came out ~half magnitude (1.0*1.0 -> 0.5).
// This version uses the verified gf16_mul/gf8_mul algorithm: full 40-bit product,
// normalize (prod[39] -> exp+1 else stay), mantissa = the 19 bits below the leading
// 1, round-to-nearest ties-to-zero (guard & (round | sticky)). Cross-checked by
// test/gf_arith_xcheck.py and test/gf_mul_sweep.py. Special-value encodings are
// preserved from the original unit (their conformance is a separate question).

`default_nettype none
module gf32_mul (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result
);

    localparam [11:0] EXP_MAX = 4095;
    localparam signed [13:0] BIAS_S    = 14'sd2047;
    localparam signed [13:0] EXP_MAX_S = 14'sd4095;

    wire             sign_a = a[31];
    wire [11:0]   exp_a  = a[30:19];
    wire [18:0]   mant_a = a[18:0];
    wire             sign_b = b[31];
    wire [11:0]   exp_b  = b[30:19];
    wire [18:0]   mant_b = b[18:0];

    wire is_zero_a = (exp_a == 12'd0) && (mant_a == 19'd0);
    wire is_zero_b = (exp_b == 12'd0) && (mant_b == 19'd0);
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == 19'd0);
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == 19'd0);
    wire is_nan_a  = (exp_a == EXP_MAX) && (mant_a != 19'd0);
    wire is_nan_b  = (exp_b == EXP_MAX) && (mant_b != 19'd0);

    wire result_sign = sign_a ^ sign_b;

    wire [39:0] full_prod = {1'b1, mant_a} * {1'b1, mant_b};  // 40-bit

    reg signed [13:0] raw_exp, final_exp;
    reg [18:0] mant_out, final_mant;
    reg [19:0]  mant_rounded;            // M+1 bits, catches mantissa overflow
    reg           guard, round_b, sticky;

    always @(*) begin
        raw_exp = 0; final_exp = 0; mant_out = 0; final_mant = 0;
        mant_rounded = 0; guard = 0; round_b = 0; sticky = 0;

        if (is_nan_a || is_nan_b)
            result = 32'hFFF80001;
        else if (is_inf_a && is_zero_b)
            result = 32'hFFF80001;
        else if (is_inf_b && is_zero_a)
            result = 32'hFFF80001;
        else if (is_inf_a || is_inf_b)
            result = result_sign ? 32'hFFF80000 : 32'h7FF80000;
        else if (is_zero_a || is_zero_b)
            result = 32'h0;
        else begin
            raw_exp = $signed({2'b00, exp_a}) + $signed({2'b00, exp_b}) - BIAS_S;

            if (full_prod[39]) begin                 // product in [2,4) -> exp+1
                raw_exp  = raw_exp + 1;
                mant_out = full_prod[38:20];
                guard    = full_prod[19];
                round_b  = full_prod[18];
                sticky   = |full_prod[17:0];
            end else begin                              // product in [1,2)
                mant_out = full_prod[37:19];
                guard    = full_prod[18];
                round_b  = full_prod[17];
                sticky   = |full_prod[16:0];
            end

            if (guard && (round_b || sticky))
                mant_rounded = {1'b0, mant_out} + 1'b1;
            else
                mant_rounded = {1'b0, mant_out};

            if (mant_rounded[19]) begin               // mantissa overflow
                final_exp  = raw_exp + 1;
                final_mant = 0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded[18:0];
            end

            if (final_exp < 0)
                result = 32'h0;                        // underflow
            else if (final_exp >= EXP_MAX_S)
                result = result_sign ? 32'hFFF80000 : 32'h7FF80000;  // overflow
            else if (final_exp == 0 && final_mant == 19'd0)
                result = 32'h0;                        // exp0/mant0 is the zero code
            else
                result = {result_sign, final_exp[11:0], final_mant};
        end
    end

endmodule
