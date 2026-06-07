// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf6_add.v
// GoldenFloat6 Addition Unit -- [S(1) | E(2) | M(3)], bias 2^(E-1)-1.
// value = (-1)^S (1 + M/2^3) 2^(E-bias).
//
// Rule-derived format: e = round((N-1)/phi^2) = round(5/phi^2) = 2
//   mant = 5-2 = 3, bias = 2^(2-1)-1 = 1, EXP_MAX = 2^2-1 = 3.
// Follows the canonical gf12_add / gf20_add algorithm.
// Status: \Conj -- Fpath = "tb passes + post-silicon vector match if/when
//   shuttle slot allocated". No shuttle slot currently assigned.

`default_nettype none
module gf6_add (
    input  wire [5:0] a,
    input  wire [5:0] b,
    output reg  [5:0] result
);

    localparam [1:0] EXP_MAX = 2'd3;
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

    wire a_larger = (exp_a > exp_b) || ((exp_a == exp_b) && (mant_a >= mant_b));

    reg        big_sign, small_sign, result_sign;
    reg [1:0] big_exp, small_exp;
    reg [2:0] big_m, small_m;
    reg [6:0] big_ext, small_ext, shifted;   // {1, mant, 3 guard bits}
    reg [2:0]  shamt;
    reg            sticky_shift;
    reg [7:0] sum_m;                          // room for add carry
    reg signed [3:0] rexp;
    reg [2:0]  mant_out;
    reg [3:0]   mant_rounded;                    // M+1 bits, catches overflow
    reg            guard, round_b, sticky, round_up;

    always @(*) begin
        big_sign = 0; small_sign = 0; result_sign = 0;
        big_exp = 0; small_exp = 0; big_m = 0; small_m = 0;
        big_ext = 0; small_ext = 0; shifted = 0; shamt = 0; sticky_shift = 0;
        sum_m = 0; rexp = 0; mant_out = 0; mant_rounded = 0;
        guard = 0; round_b = 0; sticky = 0; round_up = 0;

        if (is_nan_a || is_nan_b)
            result = 6'h39;
        else if (is_inf_a && is_inf_b && (sign_a != sign_b))
            result = 6'h39;
        else if (is_inf_a)
            result = sign_a ? 6'h38 : 6'h18;
        else if (is_inf_b)
            result = sign_b ? 6'h38 : 6'h18;
        else if (is_zero_a && is_zero_b)
            result = 6'h0;
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

            if (shamt >= 7)
                begin shifted = 0; sticky_shift = |small_ext; end
            else begin
                shifted = small_ext >> shamt;
                sticky_shift = |(small_ext & ((7'd1 << shamt) - 7'd1));
            end

            result_sign = big_sign;
            rexp = $signed({2'b0, big_exp});

            if (big_sign == small_sign)
                sum_m = {1'b0, big_ext} + {1'b0, shifted};
            else
                sum_m = {1'b0, big_ext} - {1'b0, shifted};

            if (sum_m == 0) begin
                result = 6'h0;
            end else begin
                if (sum_m[7]) begin
                    rexp = rexp + 4'sd1;
                    mant_out = sum_m[6:4];
                    guard = sum_m[3];
                    round_b = sum_m[2];
                    sticky = (|sum_m[1:0]) | sticky_shift;
                end
                else if (sum_m[6]) begin
                    mant_out = sum_m[5:3];
                    guard = sum_m[2];
                    round_b = sum_m[1];
                    sticky = (|sum_m[0:0]) | sticky_shift;
                end
                else if (sum_m[5]) begin
                    rexp = rexp - 4'sd1;
                    mant_out = sum_m[4:2];
                    guard = sum_m[1];
                    round_b = sum_m[0];
                    sticky = sticky_shift;
                end
                else if (sum_m[4]) begin
                    rexp = rexp - 4'sd2;
                    mant_out = sum_m[3:1];
                    guard = sum_m[0];
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[3]) begin
                    rexp = rexp - 4'sd3;
                    mant_out = sum_m[2:0];
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[2]) begin
                    rexp = rexp - 4'sd4;
                    mant_out = {sum_m[1:0], 1'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else if (sum_m[1]) begin
                    rexp = rexp - 4'sd5;
                    mant_out = {sum_m[0:0], 2'd0};
                    guard = 1'b0;
                    round_b = 1'b0;
                    sticky = sticky_shift;
                end
                else begin
                    mant_out = 3'd0;
                    guard = 1'b0; round_b = 1'b0; sticky = sticky_shift;
                end

                round_up     = guard && (round_b || sticky || mant_out[0]);
                mant_rounded = {1'b0, mant_out} + (round_up ? 4'd1 : 4'd0);
                if (mant_rounded[3]) begin
                    rexp     = rexp + 4'sd1;
                    mant_out = 3'd0;
                end else begin
                    mant_out = mant_rounded[2:0];
                end

                if (rexp < 0)
                    result = result_sign ? 6'h20 : 6'h0;
                else if (rexp >= EXP_MAX_S)
                    result = result_sign ? 6'h38 : 6'h18;
                else if (rexp == 0 && mant_out == 3'd0)
                    result = result_sign ? 6'h20 : 6'h0;
                else
                    result = {result_sign, rexp[1:0], mant_out};
            end
        end
    end

endmodule