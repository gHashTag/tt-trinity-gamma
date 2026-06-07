// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf96_add.v
// GoldenFloat96 Addition Unit -- [S(1) | E(36) | M(59)], bias 2^(E-1)-1.
// value = (-1)^S (1 + M/2^59) 2^(E-bias).
//
// Rule-derived format: e = round((N-1)/phi^2) = round(95/phi^2) = 36
//   mant = 95-36 = 59, bias = 2^(36-1)-1 = 34359738367, EXP_MAX = 2^36-1 = 68719476735.
// Follows the canonical gf12_add / gf20_add algorithm.
// SYNTHESIS_WARN: wide intermediate, gate at top level
// Status: \Conj -- Fpath = "tb passes + post-silicon vector match if/when
//   shuttle slot allocated". No shuttle slot currently assigned.

`default_nettype none
module gf96_add (
    input  wire [95:0] a,
    input  wire [95:0] b,
    output reg  [95:0] result
);

    localparam [35:0] EXP_MAX = 36'd68719476735;
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

    wire a_larger = (exp_a > exp_b) || ((exp_a == exp_b) && (mant_a >= mant_b));

    reg        big_sign, small_sign, result_sign;
    reg [35:0] big_exp, small_exp;
    reg [58:0] big_m, small_m;
    reg [62:0] big_ext, small_ext, shifted;   // {1, mant, 3 guard bits}
    reg [36:0]  shamt;
    reg            sticky_shift;
    reg [63:0] sum_m;                          // room for add carry
    reg signed [37:0] rexp;
    reg [58:0]  mant_out;
    reg [59:0]   mant_rounded;                    // M+1 bits, catches overflow
    reg            guard, round_b, sticky, round_up;

    always @(*) begin
        big_sign = 0; small_sign = 0; result_sign = 0;
        big_exp = 0; small_exp = 0; big_m = 0; small_m = 0;
        big_ext = 0; small_ext = 0; shifted = 0; shamt = 0; sticky_shift = 0;
        sum_m = 0; rexp = 0; mant_out = 0; mant_rounded = 0;
        guard = 0; round_b = 0; sticky = 0; round_up = 0;

        if (is_nan_a || is_nan_b)
            result = 96'hFFFFFFFFF800000000000001;
        else if (is_inf_a && is_inf_b && (sign_a != sign_b))
            result = 96'hFFFFFFFFF800000000000001;
        else if (is_inf_a)
            result = sign_a ? 96'hFFFFFFFFF800000000000000 : 96'h7FFFFFFFF800000000000000;
        else if (is_inf_b)
            result = sign_b ? 96'hFFFFFFFFF800000000000000 : 96'h7FFFFFFFF800000000000000;
        else if (is_zero_a && is_zero_b)
            result = 96'h0;
        else if (is_zero_a)
            result = b;
        else if (is_zero_b)
            result = a;
        else begin
            if (a_larger) begin
                big_sign = sign_a; big_exp = exp_a; big_m = mant_a;
                small_sign = sign_b; small_exp = exp_b; small_m = mant_b;
            end else begin
                big_sign = sign_b; big_exp = exp_b; big_m = mant_b;
                small_sign = sign_a; small_exp = exp_a; small_m = mant_a;
            end

            big_ext   = {1'b1, big_m,   3'b0};
            small_ext = {1'b1, small_m, 3'b0};
            shamt     = big_exp - small_exp;

            if (shamt >= 63)
                begin shifted = 0; sticky_shift = |small_ext; end
            else begin
                shifted = small_ext >> shamt;
                sticky_shift = |(small_ext & ((63'd1 << shamt) - 63'd1));
            end

            result_sign = big_sign;
            rexp = $signed({2'b0, big_exp});

            if (big_sign == small_sign)
                sum_m = {1'b0, big_ext} + {1'b0, shifted};
            else
                sum_m = {1'b0, big_ext} - {1'b0, shifted};

            if (sum_m == 0) begin
                result = 96'h0;
            end else begin
                if (sum_m[63]) begin
                    rexp = rexp + 38'sd1;
                    mant_out = sum_m[62:4];
                    guard = sum_m[3];
                    round_b = sum_m[2];
                    sticky = (|sum_m[1:0]) | sticky_shift;
                end
                else if (sum_m[62]) begin
                    mant_out = sum_m[61:3];
                    guard = sum_m[2];
                    round_b = sum_m[1];
                    sticky = (|sum_m[0:0]) | sticky_shift;
                end
                else if (sum_m[61]) begin
                    rexp = rexp - 38'sd1;
                    mant_out = sum_m[60:2];
                    guard = sum_m[1];
                    round_b = sum_m[0];
                    sticky = sticky_shift;
                end
                else if (sum_m[60]) begin
                    rexp = rexp - 38'sd2;
                    mant_out = sum_m[59:1];
                    guard = sum_m[0];
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[59]) begin
                    rexp = rexp - 38'sd3;
                    mant_out = sum_m[58:0];
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[58]) begin
                    rexp = rexp - 38'sd4;
                    mant_out = {sum_m[57:0], 1'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[57]) begin
                    rexp = rexp - 38'sd5;
                    mant_out = {sum_m[56:0], 2'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[56]) begin
                    rexp = rexp - 38'sd6;
                    mant_out = {sum_m[55:0], 3'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[55]) begin
                    rexp = rexp - 38'sd7;
                    mant_out = {sum_m[54:0], 4'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[54]) begin
                    rexp = rexp - 38'sd8;
                    mant_out = {sum_m[53:0], 5'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[53]) begin
                    rexp = rexp - 38'sd9;
                    mant_out = {sum_m[52:0], 6'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[52]) begin
                    rexp = rexp - 38'sd10;
                    mant_out = {sum_m[51:0], 7'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[51]) begin
                    rexp = rexp - 38'sd11;
                    mant_out = {sum_m[50:0], 8'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[50]) begin
                    rexp = rexp - 38'sd12;
                    mant_out = {sum_m[49:0], 9'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[49]) begin
                    rexp = rexp - 38'sd13;
                    mant_out = {sum_m[48:0], 10'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[48]) begin
                    rexp = rexp - 38'sd14;
                    mant_out = {sum_m[47:0], 11'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[47]) begin
                    rexp = rexp - 38'sd15;
                    mant_out = {sum_m[46:0], 12'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[46]) begin
                    rexp = rexp - 38'sd16;
                    mant_out = {sum_m[45:0], 13'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[45]) begin
                    rexp = rexp - 38'sd17;
                    mant_out = {sum_m[44:0], 14'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[44]) begin
                    rexp = rexp - 38'sd18;
                    mant_out = {sum_m[43:0], 15'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[43]) begin
                    rexp = rexp - 38'sd19;
                    mant_out = {sum_m[42:0], 16'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[42]) begin
                    rexp = rexp - 38'sd20;
                    mant_out = {sum_m[41:0], 17'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[41]) begin
                    rexp = rexp - 38'sd21;
                    mant_out = {sum_m[40:0], 18'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[40]) begin
                    rexp = rexp - 38'sd22;
                    mant_out = {sum_m[39:0], 19'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[39]) begin
                    rexp = rexp - 38'sd23;
                    mant_out = {sum_m[38:0], 20'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[38]) begin
                    rexp = rexp - 38'sd24;
                    mant_out = {sum_m[37:0], 21'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[37]) begin
                    rexp = rexp - 38'sd25;
                    mant_out = {sum_m[36:0], 22'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[36]) begin
                    rexp = rexp - 38'sd26;
                    mant_out = {sum_m[35:0], 23'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[35]) begin
                    rexp = rexp - 38'sd27;
                    mant_out = {sum_m[34:0], 24'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[34]) begin
                    rexp = rexp - 38'sd28;
                    mant_out = {sum_m[33:0], 25'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[33]) begin
                    rexp = rexp - 38'sd29;
                    mant_out = {sum_m[32:0], 26'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[32]) begin
                    rexp = rexp - 38'sd30;
                    mant_out = {sum_m[31:0], 27'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[31]) begin
                    rexp = rexp - 38'sd31;
                    mant_out = {sum_m[30:0], 28'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[30]) begin
                    rexp = rexp - 38'sd32;
                    mant_out = {sum_m[29:0], 29'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[29]) begin
                    rexp = rexp - 38'sd33;
                    mant_out = {sum_m[28:0], 30'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[28]) begin
                    rexp = rexp - 38'sd34;
                    mant_out = {sum_m[27:0], 31'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[27]) begin
                    rexp = rexp - 38'sd35;
                    mant_out = {sum_m[26:0], 32'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[26]) begin
                    rexp = rexp - 38'sd36;
                    mant_out = {sum_m[25:0], 33'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[25]) begin
                    rexp = rexp - 38'sd37;
                    mant_out = {sum_m[24:0], 34'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[24]) begin
                    rexp = rexp - 38'sd38;
                    mant_out = {sum_m[23:0], 35'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[23]) begin
                    rexp = rexp - 38'sd39;
                    mant_out = {sum_m[22:0], 36'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[22]) begin
                    rexp = rexp - 38'sd40;
                    mant_out = {sum_m[21:0], 37'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[21]) begin
                    rexp = rexp - 38'sd41;
                    mant_out = {sum_m[20:0], 38'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[20]) begin
                    rexp = rexp - 38'sd42;
                    mant_out = {sum_m[19:0], 39'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[19]) begin
                    rexp = rexp - 38'sd43;
                    mant_out = {sum_m[18:0], 40'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[18]) begin
                    rexp = rexp - 38'sd44;
                    mant_out = {sum_m[17:0], 41'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[17]) begin
                    rexp = rexp - 38'sd45;
                    mant_out = {sum_m[16:0], 42'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[16]) begin
                    rexp = rexp - 38'sd46;
                    mant_out = {sum_m[15:0], 43'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[15]) begin
                    rexp = rexp - 38'sd47;
                    mant_out = {sum_m[14:0], 44'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[14]) begin
                    rexp = rexp - 38'sd48;
                    mant_out = {sum_m[13:0], 45'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[13]) begin
                    rexp = rexp - 38'sd49;
                    mant_out = {sum_m[12:0], 46'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[12]) begin
                    rexp = rexp - 38'sd50;
                    mant_out = {sum_m[11:0], 47'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[11]) begin
                    rexp = rexp - 38'sd51;
                    mant_out = {sum_m[10:0], 48'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[10]) begin
                    rexp = rexp - 38'sd52;
                    mant_out = {sum_m[9:0], 49'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[9]) begin
                    rexp = rexp - 38'sd53;
                    mant_out = {sum_m[8:0], 50'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[8]) begin
                    rexp = rexp - 38'sd54;
                    mant_out = {sum_m[7:0], 51'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[7]) begin
                    rexp = rexp - 38'sd55;
                    mant_out = {sum_m[6:0], 52'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[6]) begin
                    rexp = rexp - 38'sd56;
                    mant_out = {sum_m[5:0], 53'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[5]) begin
                    rexp = rexp - 38'sd57;
                    mant_out = {sum_m[4:0], 54'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[4]) begin
                    rexp = rexp - 38'sd58;
                    mant_out = {sum_m[3:0], 55'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[3]) begin
                    rexp = rexp - 38'sd59;
                    mant_out = {sum_m[2:0], 56'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[2]) begin
                    rexp = rexp - 38'sd60;
                    mant_out = {sum_m[1:0], 57'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[1]) begin
                    rexp = rexp - 38'sd61;
                    mant_out = {sum_m[0:0], 58'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else begin
                    mant_out = 59'd0;
                    guard = 1'b0; round_b = 1'b0; sticky = sticky_shift;
                end

                round_up     = guard && (round_b || sticky || mant_out[0]);
                mant_rounded = {1'b0, mant_out} + (round_up ? 60'd1 : 60'd0);
                if (mant_rounded[59]) begin
                    rexp     = rexp + 38'sd1;
                    mant_out = 59'd0;
                end else begin
                    mant_out = mant_rounded[58:0];
                end

                if (rexp < 0)
                    result = result_sign ? 96'h800000000000000000000000 : 96'h0;
                else if (rexp >= EXP_MAX_S)
                    result = result_sign ? 96'hFFFFFFFFF800000000000000 : 96'h7FFFFFFFF800000000000000;
                else if (rexp == 0 && mant_out == 59'd0)
                    result = result_sign ? 96'h800000000000000000000000 : 96'h0;
                else
                    result = {result_sign, rexp[35:0], mant_out};
            end
        end
    end

endmodule