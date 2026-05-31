// Corrected gf8_mul (GF8 = 1/3/4, bias 3).
// Bug in original: product of two 5-bit mantissas is 10-bit [9:0], but
// mant_product was [8:0] (truncated bit9) and normalization checked bit8 -
// which the implicit 1*1 always sets -> exp always incremented (0.25*1.0->0.5).
// Fix: 10-bit product; leading 1 is at bit9 (va*vb in [2,4)) or bit8 ([1,2)).
`default_nettype none
module gf8_mul (
    input  wire [7:0] a,
    input  wire [7:0] b,
    output reg  [7:0] result
);
    localparam BIAS = 3'd3;
    localparam EXP_MAX = 3'd7;
    wire       sign_a = a[7]; wire [2:0] exp_a = a[6:4]; wire [3:0] mant_a = a[3:0];
    wire       sign_b = b[7]; wire [2:0] exp_b = b[6:4]; wire [3:0] mant_b = b[3:0];
    wire is_zero_a=(exp_a==0)&&(mant_a==0); wire is_zero_b=(exp_b==0)&&(mant_b==0);
    wire is_inf_a=(exp_a==EXP_MAX)&&(mant_a==0); wire is_inf_b=(exp_b==EXP_MAX)&&(mant_b==0);
    wire is_nan_a=(exp_a==EXP_MAX)&&(mant_a!=0); wire is_nan_b=(exp_b==EXP_MAX)&&(mant_b!=0);
    wire result_sign = sign_a ^ sign_b;

    reg signed [5:0] exp_product;
    reg [9:0] mant_product;        // FIX: 10-bit (was [8:0])
    reg [4:0] norm;                // {leading1, 4 mantissa bits}, +1 bit for rounding carry
    reg       guard;

    always @(*) begin
        if (is_nan_a || is_nan_b)                       result = 8'hF1;
        else if (is_inf_a && is_zero_b)                 result = 8'hF1;
        else if (is_inf_b && is_zero_a)                 result = 8'hF1;
        else if (is_inf_a || is_inf_b)                  result = result_sign ? 8'hF0 : 8'h70;
        else if (is_zero_a || is_zero_b)                result = 8'h00;
        else begin
            exp_product  = $signed({3'b0,exp_a}) + $signed({3'b0,exp_b}) - $signed({3'b0,BIAS});
            mant_product = {1'b1, mant_a} * {1'b1, mant_b};
            if (mant_product[9]) begin          // [2,4): exp+1, leading 1 at bit9
                exp_product = exp_product + 6'sd1;
                norm  = {1'b1, mant_product[8:5]};
                guard = mant_product[4];
            end else begin                       // [1,2): leading 1 at bit8
                norm  = {1'b1, mant_product[7:4]};
                guard = mant_product[3];
            end
            if (guard) norm = norm + 5'd1;
            if (norm == 5'd0) exp_product = exp_product + 6'sd1;   // rounding carry-out
            if (exp_product <= 0)
                result = result_sign ? 8'h80 : 8'h00;
            else if (exp_product >= $signed({3'b0,EXP_MAX}))
                result = result_sign ? 8'hF0 : 8'h70;
            else
                result = {result_sign, exp_product[2:0], norm[3:0]};
        end
    end
endmodule
