// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf96_mul.v
// GoldenFloat96 Multiplication Unit -- [S(1) | E(36) | M(59)], bias 2^(E-1)-1.
// value = (-1)^S (1 + M/2^59) 2^(E-bias).
//
// Rule-derived format: e = round((N-1)/phi^2) = round(95/phi^2) = 36
//   mant = 95-36 = 59, bias = 2^(36-1)-1 = 34359738367, EXP_MAX = 2^36-1 = 68719476735.
// Follows the canonical gf12_mul / gf20_mul algorithm:
//   full (M+1)x(M+1) = 120-bit product, normalize on prod[119], mantissa = 59 bits
//   below leading 1, round-to-nearest ties-to-zero (guard & (round|sticky)).
// SYNTHESIS_WARN: wide intermediate, gate at top level
//   The 120-bit multiplier ((M+1)=60 bits each side) is a significant combinational
//   resource. At synthesis time, pipeline or split-radix decomposition should be
//   applied at the top level if timing closure requires it.
// Status: \Conj -- Fpath = "tb passes + post-silicon vector match if/when
//   shuttle slot allocated". No shuttle slot currently assigned.

`default_nettype none
module gf96_mul (
    input  wire [95:0] a,
    input  wire [95:0] b,
    output reg  [95:0] result
);

    localparam [35:0] EXP_MAX = 36'd68719476735;
    localparam signed [37:0] BIAS_S    = 38'sd34359738367;
    localparam signed [37:0] EXP_MAX_S = 38'sd68719476735;

    wire             sign_a = a[95];
    wire [35:0]   exp_a  = a[94:59];
    wire [58:0]   mant_a = a[58:0];
    wire             sign_b = b[95];
    wire [35:0]   exp_b  = b[94:59];
    wire [58:0]   mant_b = b[58:0];

    wire is_zero_a = (exp_a == 36'd0) && (mant_a == 59'd0);
    wire is_zero_b = (exp_b == 36'd0) && (mant_b == 59'd0);
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == 59'd0);
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == 59'd0);
    wire is_nan_a  = (exp_a == EXP_MAX) && (mant_a != 59'd0);
    wire is_nan_b  = (exp_b == EXP_MAX) && (mant_b != 59'd0);

    wire result_sign = sign_a ^ sign_b;

    // SYNTHESIS_WARN: wide intermediate, gate at top level
    wire [119:0] full_prod = {1'b1, mant_a} * {1'b1, mant_b};  // 120-bit

    reg signed [37:0] raw_exp, final_exp;
    reg [58:0] mant_out, final_mant;
    reg [59:0]  mant_rounded;            // M+1 bits, catches mantissa overflow
    reg           guard, round_b, sticky;

    always @(*) begin
        raw_exp = 0; final_exp = 0; mant_out = 0; final_mant = 0;
        mant_rounded = 0; guard = 0; round_b = 0; sticky = 0;

        if (is_nan_a || is_nan_b)
            result = 96'hFFFFFFFFF800000000000001;
        else if (is_inf_a && is_zero_b)
            result = 96'hFFFFFFFFF800000000000001;
        else if (is_inf_b && is_zero_a)
            result = 96'hFFFFFFFFF800000000000001;
        else if (is_inf_a || is_inf_b)
            result = result_sign ? 96'hFFFFFFFFF800000000000000 : 96'h7FFFFFFFF800000000000000;
        else if (is_zero_a || is_zero_b)
            result = 96'h0;
        else begin
            raw_exp = $signed({2'b00, exp_a}) + $signed({2'b00, exp_b}) - BIAS_S;

            if (full_prod[119]) begin                // product in [2,4) -> exp+1
                raw_exp  = raw_exp + 1;
                mant_out = full_prod[118:60];
                guard    = full_prod[59];
                round_b  = full_prod[58];
                sticky   = |full_prod[57:0];
            end else begin                              // product in [1,2)
                mant_out = full_prod[117:59];
                guard    = full_prod[58];
                round_b  = full_prod[57];
                sticky   = |full_prod[56:0];
            end

            if (guard && (round_b || sticky))
                mant_rounded = {1'b0, mant_out} + 1'b1;
            else
                mant_rounded = {1'b0, mant_out};

            if (mant_rounded[59]) begin               // mantissa overflow
                final_exp  = raw_exp + 1;
                final_mant = 0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded[58:0];
            end

            if (final_exp < 0)
                result = 96'h0;                        // underflow
            else if (final_exp >= EXP_MAX_S)
                result = result_sign ? 96'hFFFFFFFFF800000000000000 : 96'h7FFFFFFFF800000000000000;  // overflow
            else if (final_exp == 0 && final_mant == 59'd0)
                result = 96'h0;                        // exp0/mant0 is the zero code
            else
                result = {result_sign, final_exp[35:0], final_mant};
        end
    end

endmodule
