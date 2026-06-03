// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf20_mul.v
// GoldenFloat20 Multiplication Unit -- [S(1) | E(7) | M(12)], bias 2^(E-1)-1.
// value = (-1)^S (1 + M/2^12) 2^(E-bias).
//
// Rewritten 2026-06 (test/gen_gf_mul_fix.py). The previous version declared
// mant_product 2 bits too narrow (24 bits, not 26), truncating the leading
// bit of the (M+1)x(M+1) product, and bumped the exponent on rounding without
// incrementing the mantissa -- products came out ~half magnitude (1.0*1.0 -> 0.5).
// This version uses the verified gf16_mul/gf8_mul algorithm: full 26-bit product,
// normalize (prod[25] -> exp+1 else stay), mantissa = the 12 bits below the leading
// 1, round-to-nearest ties-to-zero (guard & (round | sticky)). Cross-checked by
// test/gf_arith_xcheck.py and test/gf_mul_sweep.py. Special-value encodings are
// preserved from the original unit (their conformance is a separate question).

`default_nettype none
module gf20_mul (
    input  wire [19:0] a,
    input  wire [19:0] b,
    output reg  [19:0] result
);

    localparam [6:0] EXP_MAX = 127;
    localparam signed [8:0] BIAS_S    = 9'sd63;
    localparam signed [8:0] EXP_MAX_S = 9'sd127;

    wire             sign_a = a[19];
    wire [6:0]   exp_a  = a[18:12];
    wire [11:0]   mant_a = a[11:0];
    wire             sign_b = b[19];
    wire [6:0]   exp_b  = b[18:12];
    wire [11:0]   mant_b = b[11:0];

    wire is_zero_a = (exp_a == 7'd0) && (mant_a == 12'd0);
    wire is_zero_b = (exp_b == 7'd0) && (mant_b == 12'd0);
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == 12'd0);
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == 12'd0);
    wire is_nan_a  = (exp_a == EXP_MAX) && (mant_a != 12'd0);
    wire is_nan_b  = (exp_b == EXP_MAX) && (mant_b != 12'd0);

    wire result_sign = sign_a ^ sign_b;

    wire [25:0] full_prod = {1'b1, mant_a} * {1'b1, mant_b};  // 26-bit

    reg signed [8:0] raw_exp, final_exp;
    reg [11:0] mant_out, final_mant;
    reg [12:0]  mant_rounded;            // M+1 bits, catches mantissa overflow
    reg           guard, round_b, sticky;

    always @(*) begin
        raw_exp = 0; final_exp = 0; mant_out = 0; final_mant = 0;
        mant_rounded = 0; guard = 0; round_b = 0; sticky = 0;

        if (is_nan_a || is_nan_b)
            result = 20'hFF801;
        else if (is_inf_a && is_zero_b)
            result = 20'hFF801;
        else if (is_inf_b && is_zero_a)
            result = 20'hFF801;
        else if (is_inf_a || is_inf_b)
            result = result_sign ? 20'hFF800 : 20'h7F800;
        else if (is_zero_a || is_zero_b)
            result = 20'h00000;
        else begin
            raw_exp = $signed({2'b00, exp_a}) + $signed({2'b00, exp_b}) - BIAS_S;

            if (full_prod[25]) begin                 // product in [2,4) -> exp+1
                raw_exp  = raw_exp + 1;
                mant_out = full_prod[24:13];
                guard    = full_prod[12];
                round_b  = full_prod[11];
                sticky   = |full_prod[10:0];
            end else begin                              // product in [1,2)
                mant_out = full_prod[23:12];
                guard    = full_prod[11];
                round_b  = full_prod[10];
                sticky   = |full_prod[9:0];
            end

            if (guard && (round_b || sticky))
                mant_rounded = {1'b0, mant_out} + 1'b1;
            else
                mant_rounded = {1'b0, mant_out};

            if (mant_rounded[12]) begin               // mantissa overflow
                final_exp  = raw_exp + 1;
                final_mant = 0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded[11:0];
            end

            if (final_exp < 0)
                result = 20'h00000;                        // underflow
            else if (final_exp >= EXP_MAX_S)
                result = result_sign ? 20'hFF800 : 20'h7F800;  // overflow
            else if (final_exp == 0 && final_mant == 12'd0)
                result = 20'h00000;                        // exp0/mant0 is the zero code
            else
                result = {result_sign, final_exp[6:0], final_mant};
        end
    end

endmodule
