// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf10_mul.v
// GoldenFloat10 Multiplication Unit -- [S(1) | E(3) | M(6)], bias 2^(E-1)-1.
// value = (-1)^S (1 + M/2^6) 2^(E-bias).
//
// Rule-derived format: e = round((N-1)/phi^2) = round(9/phi^2) = 3
//   mant = 9-3 = 6, bias = 2^(3-1)-1 = 3, EXP_MAX = 2^3-1 = 7.
// Follows the canonical gf12_mul / gf20_mul algorithm:
//   full (M+1)x(M+1) = 14-bit product, normalize on prod[13], mantissa = 6 bits
//   below leading 1, round-to-nearest ties-to-zero (guard & (round|sticky)).
// Status: \Conj -- Fpath = "tb passes + post-silicon vector match if/when
//   shuttle slot allocated". No shuttle slot currently assigned.

`default_nettype none
module gf10_mul (
    input  wire [9:0] a,
    input  wire [9:0] b,
    output reg  [9:0] result
);

    localparam [2:0] EXP_MAX = 3'd7;
    localparam signed [4:0] BIAS_S    = 5'sd3;
    localparam signed [4:0] EXP_MAX_S = 5'sd7;

    wire             sign_a = a[9];
    wire [2:0]   exp_a  = a[8:6];
    wire [5:0]   mant_a = a[5:0];
    wire             sign_b = b[9];
    wire [2:0]   exp_b  = b[8:6];
    wire [5:0]   mant_b = b[5:0];

    wire is_zero_a = (exp_a == 3'd0) && (mant_a == 6'd0);
    wire is_zero_b = (exp_b == 3'd0) && (mant_b == 6'd0);
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == 6'd0);
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == 6'd0);
    wire is_nan_a  = (exp_a == EXP_MAX) && (mant_a != 6'd0);
    wire is_nan_b  = (exp_b == EXP_MAX) && (mant_b != 6'd0);

    wire result_sign = sign_a ^ sign_b;

    wire [13:0] full_prod = {1'b1, mant_a} * {1'b1, mant_b};  // 14-bit

    reg signed [4:0] raw_exp, final_exp;
    reg [5:0] mant_out, final_mant;
    reg [6:0]  mant_rounded;            // M+1 bits, catches mantissa overflow
    reg           guard, round_b, sticky;

    always @(*) begin
        raw_exp = 0; final_exp = 0; mant_out = 0; final_mant = 0;
        mant_rounded = 0; guard = 0; round_b = 0; sticky = 0;

        if (is_nan_a || is_nan_b)
            result = 10'h3C1;
        else if (is_inf_a && is_zero_b)
            result = 10'h3C1;
        else if (is_inf_b && is_zero_a)
            result = 10'h3C1;
        else if (is_inf_a || is_inf_b)
            result = result_sign ? 10'h3C0 : 10'h1C0;
        else if (is_zero_a || is_zero_b)
            result = 10'h0;
        else begin
            raw_exp = $signed({2'b00, exp_a}) + $signed({2'b00, exp_b}) - BIAS_S;

            if (full_prod[13]) begin                 // product in [2,4) -> exp+1
                raw_exp  = raw_exp + 1;
                mant_out = full_prod[12:7];
                guard    = full_prod[6];
                round_b  = full_prod[5];
                sticky   = |full_prod[4:0];
            end else begin                              // product in [1,2)
                mant_out = full_prod[11:6];
                guard    = full_prod[5];
                round_b  = full_prod[4];
                sticky   = |full_prod[3:0];
            end

            if (guard && (round_b || sticky))
                mant_rounded = {1'b0, mant_out} + 1'b1;
            else
                mant_rounded = {1'b0, mant_out};

            if (mant_rounded[6]) begin               // mantissa overflow
                final_exp  = raw_exp + 1;
                final_mant = 0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded[5:0];
            end

            if (final_exp < 0)
                result = 10'h0;                        // underflow
            else if (final_exp >= EXP_MAX_S)
                result = result_sign ? 10'h3C0 : 10'h1C0;  // overflow
            else if (final_exp == 0 && final_mant == 6'd0)
                result = 10'h0;                        // exp0/mant0 is the zero code
            else
                result = {result_sign, final_exp[2:0], final_mant};
        end
    end

endmodule
