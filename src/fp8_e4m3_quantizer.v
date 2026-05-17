// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/fp8_e4m3_quantizer.v
// FP8 E4M3 Quantization Unit (OCP FP8)
// Format: [S(1) | EXP(4) | MANT(3)], bias = 7
// Used in Transformer inference acceleration

`default_nettype none
module fp8_e4m3_quantizer (
    input  wire signed [15:0] fp16_in,   // FP16 input
    output reg  [7:0]    fp8_out       // FP8 E4M3 output
);

    wire        sign = fp16_in[15];
    wire [4:0]  exp16 = fp16_in[14:10];
    wire [9:0]  mant16 = fp16_in[9:0];

    // FP16 bias = 15, FP8 bias = 7
    // exp8 = exp16 - 15 + 7 = exp16 - 8

    wire [4:0]  exp8 = (exp16 >= 5'd8) ? exp16 - 5'd8 : 5'd0;
    wire [2:0]  mant8 = mant16[9:7];

    reg  [4:0]  exp_clamped;
    reg  [3:0]  mant_rounded;
    reg  [3:0]  sticky;

    always @(*) begin
        // Check for special values
        if (exp16 == 5'd31) begin
            // Infinity or NaN in FP16
            if (mant16 == 10'd0)
                fp8_out = {sign, 4'd15, 3'd0};  // Infinity
            else
                fp8_out = {sign, 4'd15, 3'd1};  // NaN
        end else if (exp16 == 5'd0) begin
            // Zero or denormal in FP16
            fp8_out = {sign, 8'd0};  // Zero
        end else begin
            // Clamp exponent to FP8 range
            if (exp8 > 4'd14)
                exp_clamped = 4'd14;
            else if (exp8 == 5'd0)
                exp_clamped = 4'd0;
            else
                exp_clamped = exp8[3:0];

            // Round mantissa
            sticky = |mant16[6:0];
            if (mant16[7] && (mant16[6] || sticky))
                mant_rounded = mant8 + 3'd1;
            else
                mant_rounded = mant8;

            // Handle mantissa overflow
            if (mant_rounded == 4'd8 && exp_clamped < 4'd14) begin
                exp_clamped = exp_clamped + 4'd1;
                mant_rounded = 4'd0;
            end

            fp8_out = {sign, exp_clamped[3:0], mant_rounded[2:0]};
        end
    end

endmodule

// FP8 E4M3 Dequantization Unit
module fp8_e4m3_dequantizer (
    input  wire [7:0]    fp8_in,       // FP8 E4M3 input
    output reg  signed [15:0] fp16_out   // FP16 output
);

    wire        sign = fp8_in[7];
    wire [3:0]  exp8 = fp8_in[6:3];
    wire [2:0]  mant8 = fp8_in[2:0];

    reg  [4:0]  exp16;
    reg  [9:0]  mant16;

    always @(*) begin
        if (exp8 == 4'd0) begin
            // Zero or denormal (treat as zero for simplicity)
            fp16_out = {sign, 15'd0};
        end else if (exp8 == 4'd15) begin
            // Infinity or NaN
            if (mant8 == 3'd0)
                fp16_out = {sign, 5'd31, 10'd0};  // Infinity
            else
                fp16_out = {sign, 5'd31, 10'd1};  // NaN
        end else begin
            // exp16 = exp8 + 8 (bias adjustment: 15 - 7 = 8)
            exp16 = {1'b0, exp8} + 5'd8;
            mant16 = {mant8, 7'd0};  // Zero-extend mantissa
            fp16_out = {sign, exp16, mant16};
        end
    end

endmodule