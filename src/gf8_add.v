// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf8_add.v
// GoldenFloat8 Addition Unit
// Layout: [S(1) | E(3) | M(4)] - BIAS = 3, value = (-1)^S (1 + M/16) 2^(E-3).
//
// Rewritten 2026-06. The previous version mapped the post-add leading bit to the
// wrong position and the wrong exponent direction (sum_m[5] -> exp-1, sum_m[4] ->
// exp-2), so e.g. 1.0 + 1.0 produced 0.5 instead of 2.0. This version implements
// a proper float add: significands carry 3 guard bits, alignment captures a
// sticky bit, the post-add leading 1 is found by priority and renormalized to a
// fixed position, and the 4-bit result mantissa is rounded to nearest, ties to
// even. (The 3 guard bits matter for a 4-bit mantissa: a naive truncating align,
// as in the wider gf16 unit, loses up to ~16 ULP on subtractive cancellation;
// here the max error over all inputs is < 1 ULP -- see test/gf8_exhaustive.py,
// 65536/65536 pairs vs an independent value-based reference.)
// Specials: NaN=0xF1, +/-Inf=0x70/0xF0, +/-0=0x00/0x80.

`default_nettype none
module gf8_add (
    input  wire [7:0]  a,
    input  wire [7:0]  b,
    output reg  [7:0]  result
);

    localparam EXP_MAX = 3'd7;   // add works with raw exponents; bias cancels

    wire        sign_a = a[7];
    wire [2:0]  exp_a  = a[6:4];
    wire [3:0]  mant_a = a[3:0];
    wire        sign_b = b[7];
    wire [2:0]  exp_b  = b[6:4];
    wire [3:0]  mant_b = b[3:0];

    wire is_zero_a    = (exp_a == 3'd0) && (mant_a == 4'd0);
    wire is_zero_b    = (exp_b == 3'd0) && (mant_b == 4'd0);
    wire is_special_a = (exp_a == EXP_MAX);
    wire is_special_b = (exp_b == EXP_MAX);
    wire is_inf_a     = is_special_a && (mant_a == 4'd0);
    wire is_inf_b     = is_special_b && (mant_b == 4'd0);
    wire is_nan_a     = is_special_a && (mant_a != 4'd0);
    wire is_nan_b     = is_special_b && (mant_b != 4'd0);

    wire a_larger = (exp_a > exp_b) || ((exp_a == exp_b) && (mant_a >= mant_b));

    reg        big_sign, small_sign, result_sign;
    reg [2:0]  big_exp, small_exp;
    reg [3:0]  big_m, small_m;
    reg [7:0]  big_ext, small_ext, shifted;  // {1'b1, mant[3:0], 3 guard bits}
    reg [3:0]  shamt;
    reg        sticky_shift;
    reg [8:0]  sum_m;                        // 9-bit: room for add carry
    reg signed [6:0] rexp;                   // running exponent (can go negative)
    reg [3:0]  mant4;
    reg        g, r, s, round_up;
    reg [4:0]  mant_round;                   // 5-bit: catches mantissa overflow

    always @(*) begin
        big_sign = 0; small_sign = 0; result_sign = 0;
        big_exp = 0; small_exp = 0; big_m = 0; small_m = 0;
        big_ext = 0; small_ext = 0; shifted = 0; shamt = 0; sticky_shift = 0;
        sum_m = 0; rexp = 0; mant4 = 0; g = 0; r = 0; s = 0; round_up = 0;
        mant_round = 0;

        if (is_nan_a || is_nan_b)
            result = 8'hF1;
        else if (is_inf_a && is_inf_b && (sign_a != sign_b))
            result = 8'hF1;
        else if (is_inf_a)
            result = sign_a ? 8'hF0 : 8'h70;
        else if (is_inf_b)
            result = sign_b ? 8'hF0 : 8'h70;
        else if (is_zero_a && is_zero_b)
            result = 8'h00;
        else if (is_zero_a)
            result = b;
        else if (is_zero_b)
            result = a;
        else begin
            if (a_larger) begin
                big_sign  = sign_a; big_exp  = exp_a; big_m  = mant_a;
                small_sign= sign_b; small_exp= exp_b; small_m= mant_b;
            end else begin
                big_sign  = sign_b; big_exp  = exp_b; big_m  = mant_b;
                small_sign= sign_a; small_exp= exp_a; small_m= mant_a;
            end

            big_ext   = {1'b1, big_m,   3'b000};
            small_ext = {1'b1, small_m, 3'b000};
            shamt     = {1'b0, big_exp} - {1'b0, small_exp};   // 0..6

            // Align the smaller operand, capturing the OR of the bits shifted
            // out as a sticky bit (needed for correct round-to-nearest).
            if (shamt >= 4'd8) begin
                shifted = 8'd0;
                sticky_shift = |small_ext;
            end else begin
                shifted = small_ext >> shamt;
                sticky_shift = |(small_ext & ((8'd1 << shamt) - 8'd1));
            end

            result_sign = big_sign;
            rexp = $signed({4'b0, big_exp});

            if (big_sign == small_sign)
                sum_m = {1'b0, big_ext} + {1'b0, shifted};
            else
                sum_m = {1'b0, big_ext} - {1'b0, shifted};  // big >= small in mag

            if (sum_m == 9'd0) begin
                result = 8'h00;                              // exact cancellation
            end else begin
                // Renormalize: bring the leading 1 to bit7; mantissa is the next
                // 4 bits, with guard/round/sticky below.
                if (sum_m[8]) begin
                    rexp = rexp + 7'sd1;
                    mant4 = sum_m[7:4]; g = sum_m[3]; r = sum_m[2];
                    s = (|sum_m[1:0]) | sticky_shift;
                end else if (sum_m[7]) begin
                    mant4 = sum_m[6:3]; g = sum_m[2]; r = sum_m[1];
                    s = sum_m[0] | sticky_shift;
                end else if (sum_m[6]) begin
                    rexp = rexp - 7'sd1;
                    mant4 = sum_m[5:2]; g = sum_m[1]; r = sum_m[0]; s = sticky_shift;
                end else if (sum_m[5]) begin
                    rexp = rexp - 7'sd2;
                    mant4 = sum_m[4:1]; g = sum_m[0]; r = 1'b0; s = sticky_shift;
                end else if (sum_m[4]) begin
                    rexp = rexp - 7'sd3;
                    mant4 = sum_m[3:0]; g = 1'b0; r = 1'b0; s = sticky_shift;
                end else if (sum_m[3]) begin
                    rexp = rexp - 7'sd4;
                    mant4 = {sum_m[2:0], 1'b0}; s = sticky_shift;
                end else if (sum_m[2]) begin
                    rexp = rexp - 7'sd5;
                    mant4 = {sum_m[1:0], 2'b00}; s = sticky_shift;
                end else if (sum_m[1]) begin
                    rexp = rexp - 7'sd6;
                    mant4 = {sum_m[0], 3'b000}; s = sticky_shift;
                end else begin
                    rexp = rexp - 7'sd7;
                    mant4 = 4'b0000; s = sticky_shift;
                end

                round_up   = g && (r || s || mant4[0]);      // nearest, ties even
                mant_round = {1'b0, mant4} + (round_up ? 5'd1 : 5'd0);
                if (mant_round[4]) begin                     // mantissa overflow
                    rexp  = rexp + 7'sd1;
                    mant4 = 4'd0;
                end else begin
                    mant4 = mant_round[3:0];
                end

                if (rexp < 0)
                    result = result_sign ? 8'h80 : 8'h00;            // underflow
                else if (rexp >= 7)
                    result = result_sign ? 8'hF0 : 8'h70;            // overflow
                else if (rexp == 0 && mant4 == 4'd0)
                    result = result_sign ? 8'h80 : 8'h00;            // 0.125 hole
                else
                    result = {result_sign, rexp[2:0], mant4};
            end
        end
    end

endmodule
