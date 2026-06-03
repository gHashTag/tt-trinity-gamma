// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf4_add.v
// GoldenFloat4 Addition Unit - Extreme Compression
// Layout: [S(1) | E(1) | M(2)] - BIAS = 0
//
// GF4 is degenerate: with bias 0 the only finite exponent is e=0 (e=1 is the
// special code), so EVERY finite value shares exponent 2^0 and the representable
// set is just {+-0, +-1.25, +-1.5, +-1.75, +-Inf, NaN} -- the significand is
// {1,mant} = 4+mant in quarter units (e0m0 is zero, so 1.0 is NOT representable;
// the smallest nonzero magnitude is 1.25). This makes "add" a round-to-nearest
// into that tiny grid (spacing 0.25, overflow above 1.875). Rewritten 2026-06 to
// do exactly that and verified exhaustively (256/256 pairs) by test/gf4_exhaustive
// .py; the generic exponent probe (test/gf_arith_xcheck.py) skips gf4 because its
// "1.0 = exp=bias" assumption collides with the zero code when bias=0.
// Encodings: +0=0x0 -0=0x8 +Inf=0x4 -Inf=0xC NaN=0xE; 1.25/1.5/1.75 = m=1/2/3.

`default_nettype none
module gf4_add (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output reg  [3:0] result
);

    wire        sign_a = a[3];
    wire        exp_a  = a[2];
    wire [1:0]  mant_a = a[1:0];
    wire        sign_b = b[3];
    wire        exp_b  = b[2];
    wire [1:0]  mant_b = b[1:0];

    wire is_zero_a = (exp_a == 1'b0) && (mant_a == 2'd0);
    wire is_zero_b = (exp_b == 1'b0) && (mant_b == 2'd0);
    wire is_inf_a  = (exp_a == 1'b1) && (mant_a == 2'd0);
    wire is_inf_b  = (exp_b == 1'b1) && (mant_b == 2'd0);
    wire is_nan_a  = (exp_a == 1'b1) && (mant_a != 2'd0);
    wire is_nan_b  = (exp_b == 1'b1) && (mant_b != 2'd0);

    // Signed significands in quarter units (4 + mant -> 4..7); range -7..7.
    reg signed [5:0] sva, svb, sum;
    reg [5:0] mag;          // |sum| in quarter units, 0..14
    reg       rsign;

    always @(*) begin
        sva = 0; svb = 0; sum = 0; mag = 0; rsign = 0;

        if (is_nan_a || is_nan_b)
            result = 4'hE;
        else if (is_inf_a && is_inf_b && (sign_a != sign_b))
            result = 4'hE;                                  // Inf - Inf = NaN
        else if (is_inf_a)
            result = sign_a ? 4'hC : 4'h4;
        else if (is_inf_b)
            result = sign_b ? 4'hC : 4'h4;
        else if (is_zero_a && is_zero_b)
            result = 4'h0;
        else if (is_zero_a)
            result = b;
        else if (is_zero_b)
            result = a;
        else begin
            sva = sign_a ? -$signed({3'b000, 1'b1, mant_a}) : $signed({3'b000, 1'b1, mant_a});
            svb = sign_b ? -$signed({3'b000, 1'b1, mant_b}) : $signed({3'b000, 1'b1, mant_b});
            sum = sva + svb;
            if (sum == 0) begin
                result = 4'h0;
            end else begin
                rsign = sum[5];
                mag   = sum[5] ? $unsigned(-sum) : $unsigned(sum);   // 0..14 quarters
                // round to nearest grid point {0,5,6,7} quarters; >=8 -> Inf
                if (mag <= 6'd2)
                    result = rsign ? 4'h8 : 4'h0;           // -> 0
                else if (mag <= 6'd5)
                    result = {rsign, 1'b0, 2'b01};          // 1.25
                else if (mag == 6'd6)
                    result = {rsign, 1'b0, 2'b10};          // 1.5
                else if (mag == 6'd7)
                    result = {rsign, 1'b0, 2'b11};          // 1.75
                else
                    result = rsign ? 4'hC : 4'h4;           // overflow -> Inf
            end
        end
    end

endmodule
