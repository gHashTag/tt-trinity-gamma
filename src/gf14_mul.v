// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf14_mul.v
// GoldenFloat14 Multiplication Unit -- [S(1) | E(5) | M(8)], bias 2^(E-1)-1.
// value = (-1)^S (1 + M/2^8) 2^(E-bias).
//
// Rule-derived format: e = round((N-1)/phi^2) = round(13/phi^2) = 5
//   mant = 13-5 = 8, bias = 2^(5-1)-1 = 15, EXP_MAX = 2^5-1 = 31.
// Follows the canonical gf12_mul / gf20_mul algorithm:
//   full (M+1)x(M+1) = 18-bit product, normalize on prod[17], mantissa = 8 bits
//   below leading 1, round-to-nearest ties-to-zero (guard & (round|sticky)).
// Status: \Conj -- Fpath = "tb passes + post-silicon vector match if/when
//   shuttle slot allocated". No shuttle slot currently assigned.

`default_nettype none
module gf14_mul (
    input  wire [13:0] a,
    input  wire [13:0] b,
    output reg  [13:0] result
);

    localparam [4:0] EXP_MAX = 5'd31;
    localparam signed [6:0] BIAS_S    = 7'sd15;
    localparam signed [6:0] EXP_MAX_S = 7'sd31;

    wire             sign_a = a[13];
    wire [4:0]   exp_a  = a[12:8];
    wire [7:0]   mant_a = a[7:0];
    wire             sign_b = b[13];
    wire [4:0]   exp_b  = b[12:8];
    wire [7:0]   mant_b = b[7:0];

    wire is_zero_a = (exp_a == 5'd0) && (mant_a == 8'd0);
    wire is_zero_b = (exp_b == 5'd0) && (mant_b == 8'd0);
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == 8'd0);
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == 8'd0);
    wire is_nan_a  = (exp_a == EXP_MAX) && (mant_a != 8'd0);
    wire is_nan_b  = (exp_b == EXP_MAX) && (mant_b != 8'd0);

    wire result_sign = sign_a ^ sign_b;

    wire [17:0] full_prod = {1'b1, mant_a} * {1'b1, mant_b};  // 18-bit

    reg signed [6:0] raw_exp, final_exp;
    reg [7:0] mant_out, final_mant;
    reg [8:0]  mant_rounded;            // M+1 bits, catches mantissa overflow
    reg           guard, round_b, sticky;

    always @(*) begin
        raw_exp = 0; final_exp = 0; mant_out = 0; final_mant = 0;
        mant_rounded = 0; guard = 0; round_b = 0; sticky = 0;

        if (is_nan_a || is_nan_b)
            result = 14'h3F01;
        else if (is_inf_a && is_zero_b)
            result = 14'h3F01;
        else if (is_inf_b && is_zero_a)
            result = 14'h3F01;
        else if (is_inf_a || is_inf_b)
            result = result_sign ? 14'h3F00 : 14'h1F00;
        else if (is_zero_a || is_zero_b)
            result = 14'h0;
        else begin
            raw_exp = $signed({2'b00, exp_a}) + $signed({2'b00, exp_b}) - BIAS_S;

            if (full_prod[17]) begin                 // product in [2,4) -> exp+1
                raw_exp  = raw_exp + 1;
                mant_out = full_prod[16:9];
                guard    = full_prod[8];
                round_b  = full_prod[7];
                sticky   = |full_prod[6:0];
            end else begin                              // product in [1,2)
                mant_out = full_prod[15:8];
                guard    = full_prod[7];
                round_b  = full_prod[6];
                sticky   = |full_prod[5:0];
            end

            if (guard && (round_b || sticky))
                mant_rounded = {1'b0, mant_out} + 1'b1;
            else
                mant_rounded = {1'b0, mant_out};

            if (mant_rounded[8]) begin               // mantissa overflow
                final_exp  = raw_exp + 1;
                final_mant = 0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded[7:0];
            end

            if (final_exp < 0)
                result = 14'h0;                        // underflow
            else if (final_exp >= EXP_MAX_S)
                result = result_sign ? 14'h3F00 : 14'h1F00;  // overflow
            else if (final_exp == 0 && final_mant == 8'd0)
                result = 14'h0;                        // exp0/mant0 is the zero code
            else
                result = {result_sign, final_exp[4:0], final_mant};
        end
    end

endmodule
