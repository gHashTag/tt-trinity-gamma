// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf8_mul.v
// GoldenFloat8 Multiplication Unit
// Layout: [S(1) | E(3) | M(4)] - BIAS = 3, value = (-1)^S (1 + M/16) 2^(E-3).
//
// Rewritten 2026-06 to fix a normalization bug: the previous version declared
// mant_product as [8:0] (5b*5b can reach 961 -> needs 10 bits, so it TRUNCATED),
// used the wrong exp bump, and sliced the wrong mantissa bits. This version
// mirrors the VERIFIED gf16_mul normalize/round algorithm scaled to E3/M4.
// Rounding: round-to-nearest, ties toward zero (round up iff guard & (round |
// sticky)) -- identical convention to gf16_mul. Exhaustively cross-checked over
// all 65536 (a,b) pairs against an independent value-based reference; see
// test/gf8_exhaustive.py. Specials: NaN=0xF1, +/-Inf=0x70/0xF0, +/-0=0x00/0x80.

`default_nettype none
module gf8_mul (
    input  wire [7:0] a,
    input  wire [7:0] b,
    output reg  [7:0] result
);

    localparam BIAS    = 3'd3;
    localparam EXP_MAX = 3'd7;

    wire        sign_a = a[7];
    wire [2:0]  exp_a  = a[6:4];
    wire [3:0]  mant_a = a[3:0];
    wire        sign_b = b[7];
    wire [2:0]  exp_b  = b[6:4];
    wire [3:0]  mant_b = b[3:0];

    wire is_zero_a = (exp_a == 3'd0) && (mant_a == 4'd0);
    wire is_zero_b = (exp_b == 3'd0) && (mant_b == 4'd0);
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == 4'd0);
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == 4'd0);
    wire is_nan_a  = (exp_a == EXP_MAX) && (mant_a != 4'd0);
    wire is_nan_b  = (exp_b == EXP_MAX) && (mant_b != 4'd0);

    wire result_sign = sign_a ^ sign_b;

    // Full mantissas with the implicit leading 1: 5 bits each, product 10 bits.
    wire [4:0] full_mant_a = {1'b1, mant_a};
    wire [4:0] full_mant_b = {1'b1, mant_b};
    wire [9:0] mant_prod   = full_mant_a * full_mant_b;   // 16..31 * 16..31 = 256..961
    wire [6:0] exp_sum     = {4'b0, exp_a} + {4'b0, exp_b};

    reg [6:0] raw_exp;
    reg [3:0] mant_out;
    reg       guard_bit, round_bit, sticky;
    reg [4:0] mant_rounded;
    reg [6:0] final_exp;
    reg [3:0] final_mant;

    always @(*) begin
        raw_exp = 0; mant_out = 0; guard_bit = 0; round_bit = 0; sticky = 0;
        mant_rounded = 0; final_exp = 0; final_mant = 0;

        if (is_nan_a || is_nan_b)
            result = 8'hF1;
        else if ((is_zero_a && is_inf_b) || (is_zero_b && is_inf_a))
            result = 8'hF1;                                   // 0 * Inf = NaN
        else if (is_zero_a || is_zero_b)
            result = result_sign ? 8'h80 : 8'h00;             // signed zero
        else if (is_inf_a || is_inf_b)
            result = result_sign ? 8'hF0 : 8'h70;             // signed Inf
        else begin
            raw_exp = exp_sum - {4'b0, BIAS};

            // Both full mantissas have bit4 set, so mant_prod >= 256 (bit8 set);
            // bit9 set means the product is in [2,4) -> exp + 1.
            if (mant_prod[9]) begin
                raw_exp   = raw_exp + 7'd1;
                mant_out  = mant_prod[8:5];
                guard_bit = mant_prod[4];
                round_bit = mant_prod[3];
                sticky    = |mant_prod[2:0];
            end else begin
                mant_out  = mant_prod[7:4];
                guard_bit = mant_prod[3];
                round_bit = mant_prod[2];
                sticky    = |mant_prod[1:0];
            end

            if (guard_bit && (round_bit || sticky))
                mant_rounded = {1'b0, mant_out} + 5'd1;
            else
                mant_rounded = {1'b0, mant_out};

            if (mant_rounded[4]) begin                        // mantissa overflow
                final_exp  = raw_exp + 7'd1;
                final_mant = 4'd0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded[3:0];
            end

            if (final_exp[6])                                 // negative -> underflow
                result = result_sign ? 8'h80 : 8'h00;
            else if (final_exp >= {4'b0, EXP_MAX})            // overflow -> Inf
                result = result_sign ? 8'hF0 : 8'h70;
            else
                result = {result_sign, final_exp[2:0], final_mant};
        end
    end

endmodule
