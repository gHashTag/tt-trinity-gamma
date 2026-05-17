`default_nettype none
module gf256_mul (
    input  wire [255:0] a,
    input  wire [255:0] b,
    output reg  [255:0] result
);

    // GF256: 1 sign + 97 exp + 158 mant = 256 bits
    localparam BIAS    = 97'd79228162514264337593543950335;
    localparam [97:0] EXP_MAX = 98'd158456325028528675187087900672;

    wire        sign_a = a[255];
    wire [96:0] exp_a  = a[254:158];
    wire [157:0] mant_a = a[157:0];
    wire        sign_b = b[255];
    wire [96:0] exp_b  = b[254:158];
    wire [157:0] mant_b = b[157:0];

    wire is_zero_a = (exp_a == 97'd0) && (mant_a == 158'd0);
    wire is_zero_b = (exp_b == 97'd0) && (mant_b == 158'd0);
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == 158'd0);
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == 158'd0);
    wire is_nan_a = (exp_a == EXP_MAX) && (mant_a != 158'd0);
    wire is_nan_b = (exp_b == EXP_MAX) && (mant_b != 158'd0);

    wire result_sign = sign_a ^ sign_b;

    reg [96:0] exp_product;
    reg [315:0] mant_product;
    reg [157:0] normalized_mant;
    reg [97:0] product_exp;
    reg       carry_out;

    always @(*) begin
        if (is_nan_a || is_nan_b)
            result = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF801;
        else if (is_inf_a && is_zero_b)
            result = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF801;
        else if (is_inf_b && is_zero_a)
            result = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF801;
        else if (is_inf_a || is_inf_b)
            result = result_sign ? 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF800 : 256'h7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF800;
        else if (is_zero_a || is_zero_b)
            result = 256'h0000000000000000000000000000000000000000000000000000000000000000;
        else begin
            exp_product = {1'b0, exp_a} + {1'b0, exp_b} - BIAS;
            mant_product = {1'b1, mant_a} * {1'b1, mant_b};

            // Product normalization: find leading bits
            if (mant_product[315] || mant_product[314]) begin
                product_exp = exp_product + 98'd2;
                normalized_mant = mant_product[315:158];
                carry_out = mant_product[157];
            end else if (mant_product[313]) begin
                product_exp = exp_product + 98'd1;
                normalized_mant = mant_product[314:157];
                carry_out = mant_product[156];
            end else if (mant_product[312]) begin
                product_exp = exp_product;
                normalized_mant = mant_product[313:156];
                carry_out = mant_product[155];
            end else begin
                product_exp = exp_product - 98'd1;
                normalized_mant = mant_product[312:155];
                carry_out = mant_product[154];
            end

            if (carry_out) begin
                product_exp = product_exp + 98'd1;
                if (normalized_mant == 158'h3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    result = result_sign ? 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF800 : 256'h7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF800;
                else
                    result = {result_sign, product_exp[96:0], normalized_mant[157:0]};
            end else begin
                if (product_exp[97] || (product_exp[96:0] >= EXP_MAX))
                    result = result_sign ? 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF800 : 256'h7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF800;
                else if (product_exp[96:0] == 97'd0)
                    result = {result_sign, 97'd0, 158'd0};
                else
                    result = {result_sign, product_exp[96:0], normalized_mant[157:0]};
            end
        end
    end

endmodule