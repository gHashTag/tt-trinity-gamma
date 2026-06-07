// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf48_add.v
// GoldenFloat48 Addition Unit -- [S(1) | E(18) | M(29)], bias 2^(E-1)-1.
// value = (-1)^S (1 + M/2^29) 2^(E-bias).
//
// Rule-derived format: e = round((N-1)/phi^2) = round(47/phi^2) = 18
//   mant = 47-18 = 29, bias = 2^(18-1)-1 = 131071, EXP_MAX = 2^18-1 = 262143.
// Follows the canonical gf12_add / gf20_add algorithm.
// Status: \Conj -- Fpath = "tb passes + post-silicon vector match if/when
//   shuttle slot allocated". No shuttle slot currently assigned.

`default_nettype none
module gf48_add (
    input  wire [47:0] a,
    input  wire [47:0] b,
    output reg  [47:0] result
);

    localparam [17:0] EXP_MAX = 18'd262143;
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

    wire a_larger = (exp_a > exp_b) || ((exp_a == exp_b) && (mant_a >= mant_b));

    reg        big_sign, small_sign, result_sign;
    reg [17:0] big_exp, small_exp;
    reg [28:0] big_m, small_m;
    reg [32:0] big_ext, small_ext, shifted;   // {1, mant, 3 guard bits}
    reg [18:0]  shamt;
    reg            sticky_shift;
    reg [33:0] sum_m;                          // room for add carry
    reg signed [19:0] rexp;
    reg [28:0]  mant_out;
    reg [29:0]   mant_rounded;                    // M+1 bits, catches overflow
    reg            guard, round_b, sticky, round_up;

    always @(*) begin
        big_sign = 0; small_sign = 0; result_sign = 0;
        big_exp = 0; small_exp = 0; big_m = 0; small_m = 0;
        big_ext = 0; small_ext = 0; shifted = 0; shamt = 0; sticky_shift = 0;
        sum_m = 0; rexp = 0; mant_out = 0; mant_rounded = 0;
        guard = 0; round_b = 0; sticky = 0; round_up = 0;

        if (is_nan_a || is_nan_b)
            result = 48'hFFFFE0000001;
        else if (is_inf_a && is_inf_b && (sign_a != sign_b))
            result = 48'hFFFFE0000001;
        else if (is_inf_a)
            result = sign_a ? 48'hFFFFE0000000 : 48'h7FFFE0000000;
        else if (is_inf_b)
            result = sign_b ? 48'hFFFFE0000000 : 48'h7FFFE0000000;
        else if (is_zero_a && is_zero_b)
            result = 48'h0;
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

            if (shamt >= 33)
                begin shifted = 0; sticky_shift = |small_ext; end
            else begin
                shifted = small_ext >> shamt;
                sticky_shift = |(small_ext & ((33'd1 << shamt) - 33'd1));
            end

            result_sign = big_sign;
            rexp = $signed({2'b0, big_exp});

            if (big_sign == small_sign)
                sum_m = {1'b0, big_ext} + {1'b0, shifted};
            else
                sum_m = {1'b0, big_ext} - {1'b0, shifted};

            if (sum_m == 0) begin
                result = 48'h0;
            end else begin
                if (sum_m[33]) begin
                    rexp = rexp + 20'sd1;
                    mant_out = sum_m[32:4];
                    guard = sum_m[3];
                    round_b = sum_m[2];
                    sticky = (|sum_m[1:0]) | sticky_shift;
                end
                else if (sum_m[32]) begin
                    mant_out = sum_m[31:3];
                    guard = sum_m[2];
                    round_b = sum_m[1];
                    sticky = (|sum_m[0:0]) | sticky_shift;
                end
                else if (sum_m[31]) begin
                    rexp = rexp - 20'sd1;
                    mant_out = sum_m[30:2];
                    guard = sum_m[1];
                    round_b = sum_m[0];
                    sticky = sticky_shift;
                end
                else if (sum_m[30]) begin
                    rexp = rexp - 20'sd2;
                    mant_out = sum_m[29:1];
                    guard = sum_m[0];
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[29]) begin
                    rexp = rexp - 20'sd3;
                    mant_out = sum_m[28:0];
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[28]) begin
                    rexp = rexp - 20'sd4;
                    mant_out = {sum_m[27:0], 1'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[27]) begin
                    rexp = rexp - 20'sd5;
                    mant_out = {sum_m[26:0], 2'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[26]) begin
                    rexp = rexp - 20'sd6;
                    mant_out = {sum_m[25:0], 3'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[25]) begin
                    rexp = rexp - 20'sd7;
                    mant_out = {sum_m[24:0], 4'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[24]) begin
                    rexp = rexp - 20'sd8;
                    mant_out = {sum_m[23:0], 5'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[23]) begin
                    rexp = rexp - 20'sd9;
                    mant_out = {sum_m[22:0], 6'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[22]) begin
                    rexp = rexp - 20'sd10;
                    mant_out = {sum_m[21:0], 7'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[21]) begin
                    rexp = rexp - 20'sd11;
                    mant_out = {sum_m[20:0], 8'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[20]) begin
                    rexp = rexp - 20'sd12;
                    mant_out = {sum_m[19:0], 9'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[19]) begin
                    rexp = rexp - 20'sd13;
                    mant_out = {sum_m[18:0], 10'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[18]) begin
                    rexp = rexp - 20'sd14;
                    mant_out = {sum_m[17:0], 11'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[17]) begin
                    rexp = rexp - 20'sd15;
                    mant_out = {sum_m[16:0], 12'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[16]) begin
                    rexp = rexp - 20'sd16;
                    mant_out = {sum_m[15:0], 13'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[15]) begin
                    rexp = rexp - 20'sd17;
                    mant_out = {sum_m[14:0], 14'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[14]) begin
                    rexp = rexp - 20'sd18;
                    mant_out = {sum_m[13:0], 15'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[13]) begin
                    rexp = rexp - 20'sd19;
                    mant_out = {sum_m[12:0], 16'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[12]) begin
                    rexp = rexp - 20'sd20;
                    mant_out = {sum_m[11:0], 17'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[11]) begin
                    rexp = rexp - 20'sd21;
                    mant_out = {sum_m[10:0], 18'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[10]) begin
                    rexp = rexp - 20'sd22;
                    mant_out = {sum_m[9:0], 19'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[9]) begin
                    rexp = rexp - 20'sd23;
                    mant_out = {sum_m[8:0], 20'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[8]) begin
                    rexp = rexp - 20'sd24;
                    mant_out = {sum_m[7:0], 21'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[7]) begin
                    rexp = rexp - 20'sd25;
                    mant_out = {sum_m[6:0], 22'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[6]) begin
                    rexp = rexp - 20'sd26;
                    mant_out = {sum_m[5:0], 23'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[5]) begin
                    rexp = rexp - 20'sd27;
                    mant_out = {sum_m[4:0], 24'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[4]) begin
                    rexp = rexp - 20'sd28;
                    mant_out = {sum_m[3:0], 25'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[3]) begin
                    rexp = rexp - 20'sd29;
                    mant_out = {sum_m[2:0], 26'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[2]) begin
                    rexp = rexp - 20'sd30;
                    mant_out = {sum_m[1:0], 27'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[1]) begin
                    rexp = rexp - 20'sd31;
                    mant_out = {sum_m[0:0], 28'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else begin
                    mant_out = 29'd0;
                    guard = 1'b0; round_b = 1'b0; sticky = sticky_shift;
                end

                round_up     = guard && (round_b || sticky || mant_out[0]);
                mant_rounded = {1'b0, mant_out} + (round_up ? 30'd1 : 30'd0);
                if (mant_rounded[29]) begin
                    rexp     = rexp + 20'sd1;
                    mant_out = 29'd0;
                end else begin
                    mant_out = mant_rounded[28:0];
                end

                if (rexp < 0)
                    result = result_sign ? 48'h800000000000 : 48'h0;
                else if (rexp >= EXP_MAX_S)
                    result = result_sign ? 48'hFFFFE0000000 : 48'h7FFFE0000000;
                else if (rexp == 0 && mant_out == 29'd0)
                    result = result_sign ? 48'h800000000000 : 48'h0;
                else
                    result = {result_sign, rexp[17:0], mant_out};
            end
        end
    end

endmodule