// SPDX-License-Identifier: Apache-2.0
// gf16_v3_mul.v -- IEEE roundTiesToEven variant of gf16_v2_mul.
//
// The gf16 spec (t27/specs/numeric/gf16.t27) states the intended rounding mode is
// "Round-to-nearest, ties to even (IEEE 754 roundTiesToEven)". gf16_v2_mul (and the
// frozen silicon) round ties-TO-ZERO (guard & (round|sticky)); the spec's own
// gf16_encode_f32 rounds half-UP. NEITHER matches the stated standard. This variant
// rounds ties-to-even by adding the kept-LSB to the round condition:
//   round_up = guard & (round | sticky | mant_out[0]).
// It differs from gf16_v2_mul only on exact-halfway products (744/262144 unit-exp
// products = 0.28%, all 1 ULP). Verified 100% == a ties-to-even reference
// (corona/tools/gf16_rounding_conformance.py). Reference variant for a future regen
// that wants strict IEEE conformance; the fabricated dies are frozen (ties-to-zero).
//
module gf16_v3_mul (
    input  wire [15:0] a,
    input  wire [15:0] b,
    output reg  [15:0] result
);

    localparam [5:0] EXP_MAX = 63;
    localparam signed [7:0] BIAS_S    = 8'sd31;
    localparam signed [7:0] EXP_MAX_S = 8'sd63;

    wire             sign_a = a[15];
    wire [5:0]   exp_a  = a[14:9];
    wire [8:0]   mant_a = a[8:0];
    wire             sign_b = b[15];
    wire [5:0]   exp_b  = b[14:9];
    wire [8:0]   mant_b = b[8:0];

    wire is_zero_a = (exp_a == 6'd0) && (mant_a == 9'd0);
    wire is_zero_b = (exp_b == 6'd0) && (mant_b == 9'd0);
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == 9'd0);
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == 9'd0);
    wire is_nan_a  = (exp_a == EXP_MAX) && (mant_a != 9'd0);
    wire is_nan_b  = (exp_b == EXP_MAX) && (mant_b != 9'd0);

    wire result_sign = sign_a ^ sign_b;

    wire [19:0] full_prod = {1'b1, mant_a} * {1'b1, mant_b};  // 20-bit

    reg signed [7:0] raw_exp, final_exp;
    reg [8:0] mant_out, final_mant;
    reg [9:0]  mant_rounded;            // M+1 bits, catches mantissa overflow
    reg           guard, round_b, sticky;

    always @(*) begin
        raw_exp = 0; final_exp = 0; mant_out = 0; final_mant = 0;
        mant_rounded = 0; guard = 0; round_b = 0; sticky = 0;

        if (is_nan_a || is_nan_b)
            result = 16'hFE01;
        else if (is_inf_a && is_zero_b)
            result = 16'hFE01;
        else if (is_inf_b && is_zero_a)
            result = 16'hFE01;
        else if (is_inf_a || is_inf_b)
            result = result_sign ? 16'hFE00 : 16'h7E00;
        else if (is_zero_a || is_zero_b)
            result = 16'h0;
        else begin
            raw_exp = $signed({2'b00, exp_a}) + $signed({2'b00, exp_b}) - BIAS_S;

            if (full_prod[19]) begin                 // product in [2,4) -> exp+1
                raw_exp  = raw_exp + 1;
                mant_out = full_prod[18:10];
                guard    = full_prod[9];
                round_b  = full_prod[8];
                sticky   = |full_prod[7:0];
            end else begin                              // product in [1,2)
                mant_out = full_prod[17:9];
                guard    = full_prod[8];
                round_b  = full_prod[7];
                sticky   = |full_prod[6:0];
            end

            if (guard && (round_b || sticky || mant_out[0]))  // ties-to-even (RNE)
                mant_rounded = {1'b0, mant_out} + 1'b1;
            else
                mant_rounded = {1'b0, mant_out};

            if (mant_rounded[9]) begin               // mantissa overflow
                final_exp  = raw_exp + 1;
                final_mant = 0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded[8:0];
            end

            if (final_exp < 0)
                result = 16'h0;                        // underflow
            else if (final_exp >= EXP_MAX_S)
                result = result_sign ? 16'hFE00 : 16'h7E00;  // overflow
            else if (final_exp == 0 && final_mant == 9'd0)
                result = 16'h0;                        // exp0/mant0 is the zero code
            else
                result = {result_sign, final_exp[5:0], final_mant};
        end
    end

endmodule
