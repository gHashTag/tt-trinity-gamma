// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf256_add.v
// GoldenFloat256 Addition Unit (Verilog-2005 compliant)
// Layout: [S(1) | E(97) | M(158)] - phi_dist = 0.004 - BIAS = 7922816251426433759

`default_nettype none
module gf256_add (
    input  wire [255:0] a,
    input  wire [255:0] b,
    output reg  [255:0] result
);

    localparam BIAS    = 97'd79228162514264337593543950335;
    localparam [97:0] EXP_MAX = 98'd158456325028528675187087900672;

    wire        sign_a = a[255];
    wire [96:0] exp_a  = a[254:158];
    wire [157:0] mant_a = a[157:0];
    wire        sign_b = b[255];
    wire [96:0] exp_b  = b[254:158];
    wire [157:0] mant_b = b[157:0];

    wire is_zero_a    = (exp_a == 97'd0) && (mant_a == 158'd0);
    wire is_zero_b    = (exp_b == 97'd0) && (mant_b == 158'd0);
    wire is_special_a = (exp_a == EXP_MAX);
    wire is_special_b = (exp_b == EXP_MAX);
    wire is_inf_a     = is_special_a && (mant_a == 158'd0);
    wire is_inf_b     = is_special_b && (mant_b == 158'd0);
    wire is_nan_a     = is_special_a && (mant_a != 158'd0);
    wire is_nan_b     = is_special_b && (mant_b != 158'd0);

    wire a_larger = (exp_a > exp_b) || ((exp_a == exp_b) && (mant_a >= mant_b));

    reg [97:0] big_exp, shift, result_exp;
    reg [159:0] big_fm, small_fm;
    reg [160:0] sum_m;
    reg       big_sign, small_sign, result_sign;
    reg [159:0] norm;
    reg       g_bit, r_bit, s_bit;
    reg [160:0] rounded;
    reg [97:0] final_exp;
    reg [157:0] final_mant;
    reg [255:0] fr;
    reg       cancel;
    reg [7:0]  lzc;  // Leading zero counter

    always @(*) begin
        cancel = 0;
        result_exp = 0;
        norm = 0;
        g_bit = 0;
        r_bit = 0;
        s_bit = 0;
        rounded = 0;
        final_exp = 0;
        final_mant = 0;
        fr = 0;
        result_sign = 0;
        big_exp = 0;
        big_fm = 0;
        big_sign = 0;
        small_fm = 0;
        small_sign = 0;
        shift = 0;
        sum_m = 0;
        lzc = 0;

        if (is_nan_a || is_nan_b)
            result = 256'hFFFFFFFFFFF801;
        else if (is_inf_a && is_inf_b && (sign_a != sign_b))
            result = 256'hFFFFFFFFFFF801;
        else if (is_inf_a)
            result = sign_a ? 256'hFFFFFFFFFFF800 : 256'h7FFFFFFFFFF800;
        else if (is_inf_b)
            result = sign_b ? 256'hFFFFFFFFFFF800 : 256'h7FFFFFFFFFF800;
        else if (is_zero_a && is_zero_b)
            result = 256'h00000000000000000000000000000000;
        else if (is_zero_a)
            result = b;
        else if (is_zero_b)
            result = a;
        else begin
            if (a_larger) begin
                big_exp    = {1'b0, exp_a};
                big_fm     = {1'b1, mant_a};
                big_sign   = sign_a;
                small_fm   = {1'b1, mant_b};
                small_sign = sign_b;
            end else begin
                big_exp    = {1'b0, exp_b};
                big_fm     = {1'b1, mant_b};
                big_sign   = sign_b;
                small_fm   = {1'b1, mant_a};
                small_sign = sign_a;
            end

            shift = big_exp - {1'b0, (a_larger ? exp_b : exp_a)};
            result_exp = big_exp;

            // Barrel shifter for small_fm alignment
            if (shift < 98'd159)
                small_fm = small_fm >> shift;
            else
                small_fm = 161'd0;

            if (big_sign == small_sign) begin
                sum_m = {1'b0, big_fm} + {1'b0, small_fm};
                result_sign = big_sign;
            end else begin
                sum_m = {1'b0, big_fm} - {1'b0, small_fm};
                result_sign = big_sign;
                if (sum_m == 161'd0)
                    cancel = 1;
            end

            if (!cancel) begin
                if (sum_m[160]) begin
                    result_exp = result_exp + 98'd1;
                    norm  = sum_m[159:1];
                    g_bit = sum_m[0];
                    r_bit = 1'b0;
                    s_bit = 1'b0;
                end else if (sum_m[159]) begin
                    result_exp = result_exp + 98'd1;
                    norm  = sum_m[159:1];
                    g_bit = sum_m[0];
                    r_bit = 1'b0;
                    s_bit = 1'b0;
                end else begin
                    // Simplified leading zero count for Verilog-2005
                    lzc = 0;
                    if (!sum_m[158]) lzc = lzc + 1;
                    if (!sum_m[157] && lzc == 1) lzc = lzc + 1;
                    if (!sum_m[156] && lzc == 2) lzc = lzc + 1;
                    if (!sum_m[155] && lzc == 3) lzc = lzc + 1;
                    if (!sum_m[154] && lzc == 4) lzc = lzc + 1;
                    if (!sum_m[153] && lzc == 5) lzc = lzc + 1;
                    if (!sum_m[152] && lzc == 6) lzc = lzc + 1;
                    if (!sum_m[151] && lzc == 7) lzc = lzc + 1;

                    if (lzc == 0)
                        norm = sum_m[158:0];
                    else if (lzc == 1) begin
                        norm = {sum_m[157:0], 1'b0};
                        result_exp = result_exp - 98'd1;
                    end else if (lzc == 2) begin
                        norm = {sum_m[156:0], 2'b00};
                        result_exp = result_exp - 98'd2;
                    end else if (lzc == 3) begin
                        norm = {sum_m[155:0], 3'b000};
                        result_exp = result_exp - 98'd3;
                    end else if (lzc == 4) begin
                        norm = {sum_m[154:0], 4'b0000};
                        result_exp = result_exp - 98'd4;
                    end else if (lzc == 5) begin
                        norm = {sum_m[153:0], 5'b00000};
                        result_exp = result_exp - 98'd5;
                    end else if (lzc == 6) begin
                        norm = {sum_m[152:0], 6'b000000};
                        result_exp = result_exp - 98'd6;
                    end else if (lzc == 7) begin
                        norm = {sum_m[151:0], 7'b0000000};
                        result_exp = result_exp - 98'd7;
                    end else begin
                        norm = {1'b1, 158'b0};
                        result_exp = result_exp - 98'd158;
                    end

                    g_bit = 1'b0;
                    r_bit = 1'b0;
                    s_bit = 1'b0;
                end

                if (g_bit && (r_bit || s_bit))
                    rounded = norm + 161'd1;
                else
                    rounded = norm;

                if (rounded < norm) begin
                    final_exp  = result_exp + 98'd1;
                    final_mant = 158'd0;
                end else begin
                    final_exp  = result_exp;
                    final_mant = norm[157:0];
                end

                if (final_exp[97])
                    fr = result_sign ? 256'h80000000000000000000000000000000 : 256'h00000000000000000000000000000000;
                else if (final_exp[96:0] >= EXP_MAX)
                    fr = result_sign ? 256'hFFFFFFFFFFF800 : 256'h7FFFFFFFFFF800;
                else
                    fr = {result_sign, final_exp[96:0], final_mant};

                result = fr;
            end else begin
                result = 256'h00000000000000000000000000000000;
            end
        end
    end

endmodule