// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/int4_quantizer.v
// Int4 Quantization Unit (symmetric quantization)
// Range: [-8, 7], Quantization scale: 0.0625 (1/16)
// Used in model compression and inference acceleration

`default_nettype none
module int4_quantizer (
    input  wire signed [15:0] fp16_in,   // FP16/FP32 input
    input  wire [3:0]    scale_exp,    // Scale exponent (2^scale_exp)
    input  wire [2:0]    zero_point,   // Zero point offset
    output reg  [3:0]    int4_out      // Int4 output [S(1) \| D(3)]
);

    reg signed [15:0] scale;
    reg signed [15:0] scaled;
    reg signed [15:0] zeroed;
    reg signed [15:0] clamped;
    reg [3:0]          quant;

    always @(*) begin
        // Compute scale = 2^scale_exp (simplified LUT)
        case (scale_exp)
            4'd0:  scale = 16'h8000;  // 1.0
            4'd1:  scale = 16'h4000;  // 0.5
            4'd2:  scale = 16'h2000;  // 0.25
            4'd3:  scale = 16'h1000;  // 0.125
            4'd4:  scale = 16'h0800;  // 0.0625 (1/16)
            4'd5:  scale = 16'h0400;  // 0.03125 (1/32)
            4'd6:  scale = 16'h0200;  // 0.015625 (1/64)
            4'd7:  scale = 16'h0100;  // 0.0078125 (1/128)
            default: scale = 16'h0800;
        endcase

        // Scale: scaled = fp16_in >> scale_exp (R-SI-1: shift instead of *)
        case (scale_exp)
            4'd0:  scaled = fp16_in;
            4'd1:  scaled = {{1{fp16_in[15]}}, fp16_in[15:1]};
            4'd2:  scaled = {{2{fp16_in[15]}}, fp16_in[15:2]};
            4'd3:  scaled = {{3{fp16_in[15]}}, fp16_in[15:3]};
            4'd4:  scaled = {{4{fp16_in[15]}}, fp16_in[15:4]};
            4'd5:  scaled = {{5{fp16_in[15]}}, fp16_in[15:5]};
            4'd6:  scaled = {{6{fp16_in[15]}}, fp16_in[15:6]};
            4'd7:  scaled = {{7{fp16_in[15]}}, fp16_in[15:7]};
            default: scaled = {{4{fp16_in[15]}}, fp16_in[15:4]};
        endcase

        // Add zero point: zeroed = scaled + zero_point
        // zero_point is signed 3-bit [-4, 3]
        zeroed = scaled + {{13{zero_point[2]}}, zero_point};

        // Clamp to [-8, 7]
        if (zeroed >= 16'd0007)
            clamped = 16'd0007;
        else if (zeroed < -16'd0008)
            clamped = -16'd0008;
        else
            clamped = zeroed;

        // Convert to 4-bit signed [S(1) \| D(3)]
        // Negative: use two's complement
        if (clamped >= 0)
            int4_out = {1'b0, clamped[2:0]};
        else
            int4_out = {1'b1, (~clamped[2:0] + 3'b001)};
    end

endmodule

// Int4 Dequantization Unit (symmetric)
module int4_dequantizer (
    input  wire [3:0]    int4_in,      // Int4 input [S(1) \| D(3)]
    input  wire [3:0]    scale_exp,    // Scale exponent
    output reg  signed [15:0] fp16_out   // FP16 output
);

    reg signed [15:0] scale;
    reg signed [3:0]  int4_signed;
    reg signed [15:0] dequant;

    always @(*) begin
        // Compute scale
        case (scale_exp)
            4'd0:  scale = 16'h8000;  // 1.0
            4'd1:  scale = 16'h4000;  // 0.5
            4'd2:  scale = 16'h2000;  // 0.25
            4'd3:  scale = 16'h1000;  // 0.125
            4'd4:  scale = 16'h0800;  // 0.0625
            4'd5:  scale = 16'h0400;  // 0.03125
            4'd6:  scale = 16'h0200;  // 0.015625
            4'd7:  scale = 16'h0100;  // 0.0078125
            default: scale = 16'h0800;
        endcase

        // Sign-extend 3-bit magnitude to 4-bit signed
        if (int4_in[3])
            int4_signed = -{1'b0, int4_in[2:0]};
        else
            int4_signed = {1'b0, int4_in[2:0]};

        // Dequant: fp16_out = int4_signed << scale_exp (R-SI-1: shift instead of *)
        case (scale_exp)
            4'd0:  fp16_out = int4_signed;
            4'd1:  fp16_out = {int4_signed[14:0], 1'b0};
            4'd2:  fp16_out = {int4_signed[13:0], 2'b0};
            4'd3:  fp16_out = {int4_signed[12:0], 3'b0};
            4'd4:  fp16_out = {int4_signed[11:0], 4'b0};
            4'd5:  fp16_out = {int4_signed[10:0], 5'b0};
            4'd6:  fp16_out = {int4_signed[9:0],  6'b0};
            4'd7:  fp16_out = {int4_signed[8:0],  7'b0};
            default: fp16_out = {int4_signed[11:0], 4'b0};
        endcase
    end

endmodule