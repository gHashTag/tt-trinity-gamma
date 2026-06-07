// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf48_mul.v
// GoldenFloat48 Multiplication Unit -- [S(1) | E(18) | M(29)], bias 2^(E-1)-1.
// value = (-1)^S (1 + M/2^29) 2^(E-bias).
//
// Rule-derived format: e = round((N-1)/phi^2) = round(47/phi^2) = 18
//   mant = 47-18 = 29, bias = 2^(18-1)-1 = 131071, EXP_MAX = 2^18-1 = 262143.
// Follows the canonical gf12_mul / gf20_mul algorithm:
//   full (M+1)x(M+1) = 60-bit product, normalize on prod[59], mantissa = 29 bits
//   below leading 1, round-to-nearest ties-to-zero (guard & (round|sticky)).
// Status: \Conj -- Fpath = "tb passes + post-silicon vector match if/when
//   shuttle slot allocated". No shuttle slot currently assigned.

`default_nettype none
module gf48_mul (
    input  wire [47:0] a,
    input  wire [47:0] b,
    output reg  [47:0] result
);

    localparam [17:0] EXP_MAX = 18'd262143;
    localparam signed [19:0] BIAS_S    = 20'sd131071;
    localparam signed [19:0] EXP_MAX_S = 20'sd262143;

    wire             sign_a = a[47];
    wire [17:0]   exp_a  = a[46:29];
    wire [28:0]   mant_a = a[28:0];
    wire             sign_b = b[47];
    wire [17:0]   exp_b  = b[46:29];
    wire [28:0]   mant_b = b[28:0];

    wire is_zero_a = (exp_a == 18'd0) && (mant_a == 29'd0);
    wire is_zero_b = (exp_b == 18'd0) && (mant_b == 29'd0);
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == 29'd0);
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == 29'd0);
    wire is_nan_a  = (exp_a == EXP_MAX) && (mant_a != 29'd0);
    wire is_nan_b  = (exp_b == EXP_MAX) && (mant_b != 29'd0);

    wire result_sign = sign_a ^ sign_b;

    wire [59:0] full_prod = {1'b1, mant_a} * {1'b1, mant_b};  // 60-bit

    reg signed [19:0] raw_exp, final_exp;
    reg [28:0] mant_out, final_mant;
    reg [29:0]  mant_rounded;            // M+1 bits, catches mantissa overflow
    reg           guard, round_b, sticky;

    always @(*) begin
        raw_exp = 0; final_exp = 0; mant_out = 0; final_mant = 0;
        mant_rounded = 0; guard = 0; round_b = 0; sticky = 0;

        if (is_nan_a || is_nan_b)
            result = 48'hFFFFE0000001;
        else if (is_inf_a && is_zero_b)
            result = 48'hFFFFE0000001;
        else if (is_inf_b && is_zero_a)
            result = 48'hFFFFE0000001;
        else if (is_inf_a || is_inf_b)
            result = result_sign ? 48'hFFFFE0000000 : 48'h7FFFE0000000;
        else if (is_zero_a || is_zero_b)
            result = 48'h0;
        else begin
            raw_exp = $signed({2'b00, exp_a}) + $signed({2'b00, exp_b}) - BIAS_S;

            if (full_prod[59]) begin                 // product in [2,4) -> exp+1
                raw_exp  = raw_exp + 1;
                mant_out = full_prod[58:30];
                guard    = full_prod[29];
                round_b  = full_prod[28];
                sticky   = |full_prod[27:0];
            end else begin                              // product in [1,2)
                mant_out = full_prod[57:29];
                guard    = full_prod[28];
                round_b  = full_prod[27];
                sticky   = |full_prod[26:0];
            end

            if (guard && (round_b || sticky))
                mant_rounded = {1'b0, mant_out} + 1'b1;
            else
                mant_rounded = {1'b0, mant_out};

            if (mant_rounded[29]) begin               // mantissa overflow
                final_exp  = raw_exp + 1;
                final_mant = 0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded[28:0];
            end

            if (final_exp < 0)
                result = 48'h0;                        // underflow
            else if (final_exp >= EXP_MAX_S)
                result = result_sign ? 48'hFFFFE0000000 : 48'h7FFFE0000000;  // overflow
            else if (final_exp == 0 && final_mant == 29'd0)
                result = 48'h0;                        // exp0/mant0 is the zero code
            else
                result = {result_sign, final_exp[17:0], final_mant};
        end
    end

endmodule
