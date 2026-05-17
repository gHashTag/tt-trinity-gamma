// SPDX-License-Identifier: Apache-2.0
// Trinity Mantissa Multiplier — R-SI-1 compliant (zero `*`)
// Implements W-bit unsigned multiplication via partial-product shift-and-add
`default_nettype none
module tri_mant_mul #(parameter W = 11) (
    input  wire [W-1:0] a, b,
    output wire [2*W-1:0] product
);
    wire [2*W-1:0] partial [W-1:0];
    genvar i;
    generate
        for (i = 0; i < W; i = i + 1) begin : gen_pp
            assign partial[i] = b[i] ? ({{W{1'b0}}, a} << i) : {2*W{1'b0}};
        end
    endgenerate
    reg [2*W-1:0] sum;
    integer k;
    always @(*) begin
        sum = {2*W{1'b0}};
        for (k = 0; k < W; k = k + 1)
            sum = sum + partial[k];
    end
    assign product = sum;
endmodule
