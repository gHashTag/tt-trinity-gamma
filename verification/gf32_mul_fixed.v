// Corrected gf32_mul (GF32 = 1/12/19, bias 2047).
// Fix vs broken original: product of two 20-bit mantissas is 40-bit [39:0]
// (original declared [37:0] -> truncated bit38/39 -> 1.0*1.0 lost the leading 1).
// Normalized product of two [1,2) values is in [2^38, 2^40): leading 1 at bit 39
// (->[2,4), exp+1) or bit 38 (->[1,2), exp+0). Round-to-nearest on the guard bit.
`default_nettype none
module gf32_mul (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result
);
    localparam BIAS    = 12'd2047;
    localparam EXP_MAX = 12'd4095;

    wire        sign_a = a[31];
    wire [11:0] exp_a  = a[30:19];
    wire [18:0] mant_a = a[18:0];
    wire        sign_b = b[31];
    wire [11:0] exp_b  = b[30:19];
    wire [18:0] mant_b = b[18:0];

    wire is_zero_a = (exp_a == 12'd0) && (mant_a == 19'd0);
    wire is_zero_b = (exp_b == 12'd0) && (mant_b == 19'd0);
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == 19'd0);
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == 19'd0);
    wire is_nan_a  = (exp_a == EXP_MAX) && (mant_a != 19'd0);
    wire is_nan_b  = (exp_b == EXP_MAX) && (mant_b != 19'd0);
    wire result_sign = sign_a ^ sign_b;

    reg signed [13:0] exp_product;
    reg [39:0] mant_product;      // FIX: 40-bit (was [37:0])
    reg [19:0] norm;              // 1 + 19-bit mantissa (allow rounding carry at bit 19)
    reg        guard;

    always @(*) begin
        if (is_nan_a || is_nan_b)                          result = 32'hFFFFF801;
        else if (is_inf_a && is_zero_b)                    result = 32'hFFFFF801;
        else if (is_inf_b && is_zero_a)                    result = 32'hFFFFF801;
        else if (is_inf_a || is_inf_b)                     result = result_sign ? 32'hFFFFF800 : 32'h7FFF8000;
        else if (is_zero_a || is_zero_b)                   result = 32'h00000000;
        else begin
            exp_product  = $signed({2'b0, exp_a}) + $signed({2'b0, exp_b}) - $signed({2'b0, BIAS});
            mant_product = {1'b1, mant_a} * {1'b1, mant_b};

            if (mant_product[39]) begin            // product in [2,4): exp+1
                exp_product = exp_product + 14'sd1;
                norm  = {1'b1, mant_product[38:20]};
                guard = mant_product[19];
            end else begin                          // product in [1,2): leading 1 at bit 38
                norm  = {1'b1, mant_product[37:19]};
                guard = mant_product[18];
            end

            if (guard)
                norm = norm + 20'd1;
            if (norm == 20'd0)                      // rounding carried out of the 20-bit norm
                exp_product = exp_product + 14'sd1;

            // assemble / range-check
            if (exp_product <= 0)
                result = result_sign ? 32'h80000000 : 32'h00000000;     // underflow -> signed zero
            else if (exp_product >= $signed({2'b0, EXP_MAX}))
                result = result_sign ? 32'hFFFFF800 : 32'h7FFF8000;      // overflow -> inf
            else
                result = {result_sign, exp_product[11:0], norm[18:0]};
        end
    end
endmodule
