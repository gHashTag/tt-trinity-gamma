// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf6_mul.v
// GoldenFloat6 Multiplication Unit -- [S(1) | E(2) | M(3)], bias 2^(E-1)-1.
// value = (-1)^S (1 + M/2^3) 2^(E-bias).
//
// Rule-derived format: e = round((N-1)/phi^2) = round(5/phi^2) = 2
//   mant = 5-2 = 3, bias = 2^(2-1)-1 = 1, EXP_MAX = 2^2-1 = 3.
// Follows the canonical gf12_mul / gf20_mul algorithm:
//   full (M+1)x(M+1) = 8-bit product, normalize on prod[7], mantissa = 3 bits
//   below leading 1, round-to-nearest ties-to-zero (guard & (round|sticky)).
// Status: \Conj -- Fpath = "tb passes + post-silicon vector match if/when
//   shuttle slot allocated". No shuttle slot currently assigned.

`default_nettype none
module gf6_mul (
    input  wire [5:0] a,
    input  wire [5:0] b,
    output reg  [5:0] result
);

    localparam [1:0] EXP_MAX = 2'd3;
    localparam signed [3:0] BIAS_S    = 4'sd1;
    localparam signed [3:0] EXP_MAX_S = 4'sd3;

    wire             sign_a = a[5];
    wire [1:0]   exp_a  = a[4:3];
    wire [2:0]   mant_a = a[2:0];
    wire             sign_b = b[5];
    wire [1:0]   exp_b  = b[4:3];
    wire [2:0]   mant_b = b[2:0];

    wire is_zero_a = (exp_a == 2'd0) && (mant_a == 3'd0);
    wire is_zero_b = (exp_b == 2'd0) && (mant_b == 3'd0);
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == 3'd0);
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == 3'd0);
    wire is_nan_a  = (exp_a == EXP_MAX) && (mant_a != 3'd0);
    wire is_nan_b  = (exp_b == EXP_MAX) && (mant_b != 3'd0);

    wire result_sign = sign_a ^ sign_b;

    wire [7:0] full_prod = {1'b1, mant_a} * {1'b1, mant_b};  // 8-bit

    reg signed [3:0] raw_exp, final_exp;
    reg [2:0] mant_out, final_mant;
    reg [3:0]  mant_rounded;            // M+1 bits, catches mantissa overflow
    reg           guard, round_b, sticky;

    always @(*) begin
        raw_exp = 0; final_exp = 0; mant_out = 0; final_mant = 0;
        mant_rounded = 0; guard = 0; round_b = 0; sticky = 0;

        if (is_nan_a || is_nan_b)
            result = 6'h39;
        else if (is_inf_a && is_zero_b)
            result = 6'h39;
        else if (is_inf_b && is_zero_a)
            result = 6'h39;
        else if (is_inf_a || is_inf_b)
            result = result_sign ? 6'h38 : 6'h18;
        else if (is_zero_a || is_zero_b)
            result = 6'h0;
        else begin
            raw_exp = $signed({2'b00, exp_a}) + $signed({2'b00, exp_b}) - BIAS_S;

            if (full_prod[7]) begin                 // product in [2,4) -> exp+1
                raw_exp  = raw_exp + 1;
                mant_out = full_prod[6:4];
                guard    = full_prod[3];
                round_b  = full_prod[2];
                sticky   = |full_prod[1:0];
            end else begin                              // product in [1,2)
                mant_out = full_prod[5:3];
                guard    = full_prod[2];
                round_b  = full_prod[1];
                sticky   = |full_prod[0:0];
            end

            if (guard && (round_b || sticky))
                mant_rounded = {1'b0, mant_out} + 1'b1;
            else
                mant_rounded = {1'b0, mant_out};

            if (mant_rounded[3]) begin               // mantissa overflow
                final_exp  = raw_exp + 1;
                final_mant = 0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded[2:0];
            end

            if (final_exp < 0)
                result = 6'h0;                        // underflow
            else if (final_exp >= EXP_MAX_S)
                result = result_sign ? 6'h38 : 6'h18;  // overflow
            else if (final_exp == 0 && final_mant == 3'd0)
                result = 6'h0;                        // exp0/mant0 is the zero code
            else
                result = {result_sign, final_exp[1:0], final_mant};
        end
    end

endmodule
