// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/nf4_quantizer.v
// NormalFloat4 Quantization Unit (QLoRA)
// 16 levels drawn from Normal(0,1) quantiles
// Used in QLoRA for efficient 4-bit fine-tuning

`default_nettype none
module nf4_quantizer (
    input  wire signed [15:0] fp16_in,  // FP32/FP16 input
    input  wire [3:0]  scale_idx,      // Scale index
    output reg  [3:0]  nf4_out         // NF4 output (4 bits)
);

    // NF4 levels from Normal(0,1) quantiles (Q-LoRA paper)
    // Symmetric around 0, ordered from most negative to most positive
    function [3:0] nf4_index;
        input signed [3:0] idx;
        begin
            case (idx)
                4'd0:  nf4_index = 4'd8;   // -1.000
                4'd1:  nf4_index = 4'd9;   // -0.696
                4'd2:  nf4_index = 4'd10;  // -0.525
                4'd3:  nf4_index = 4'd11;  // -0.394
                4'd4:  nf4_index = 4'd12;  // -0.284
                4'd5:  nf4_index = 4'd13;  // -0.185
                4'd6:  nf4_index = 4'd14;  // -0.091
                4'd7:  nf4_index = 4'd15;  //  0.000
                4'd8:  nf4_index = 4'd15;  //  0.000 (duplicate zero)
                4'd9:  nf4_index = 4'd0;   //  0.091
                4'd10: nf4_index = 4'd1;   //  0.185
                4'd11: nf4_index = 4'd2;   //  0.284
                4'd12: nf4_index = 4'd3;   //  0.394
                4'd13: nf4_index = 4'd4;   //  0.525
                4'd14: nf4_index = 4'd5;   //  0.696
                4'd15: nf4_index = 4'd6;   //  1.000
                default: nf4_index = 4'd15;
            endcase
        end
    endfunction

    // Scale factors (simplified for hardware)
    // Real implementation would have per-layer learned scales
    reg signed [15:0] scale;
    reg signed [15:0] scaled;
    reg signed [3:0]  quant_idx;

    always @(*) begin
        // Simplified scale selection
        case (scale_idx)
            4'd0: scale = 16'h4000;  // 0.5
            4'd1: scale = 16'h2000;  // 0.25
            4'd2: scale = 16'h1000;  // 0.125
            4'd3: scale = 16'h0800;  // 0.0625
            default: scale = 16'h4000;
        endcase

        // Scale the input (R-SI-1: shift instead of *)
        case (scale_idx)
            4'd0: scaled = {{1{fp16_in[15]}}, fp16_in[15:1]};   // >> 1 (0.5)
            4'd1: scaled = {{2{fp16_in[15]}}, fp16_in[15:2]};   // >> 2 (0.25)
            4'd2: scaled = {{3{fp16_in[15]}}, fp16_in[15:3]};   // >> 3 (0.125)
            4'd3: scaled = {{4{fp16_in[15]}}, fp16_in[15:4]};   // >> 4 (0.0625)
            default: scaled = {{1{fp16_in[15]}}, fp16_in[15:1]};
        endcase

        // Quantize to NF4 range [-8, 7] then map to levels
        if (scaled >= 16'd4000)  // ~1.0
            quant_idx = 4'd15;
        else if (scaled >= 16'd3800)
            quant_idx = 4'd14;
        else if (scaled >= 16'd3500)
            quant_idx = 4'd13;
        else if (scaled >= 16'd3000)
            quant_idx = 4'd12;
        else if (scaled >= 16'd2300)
            quant_idx = 4'd11;
        else if (scaled >= 16'h1800)
            quant_idx = 4'd10;
        else if (scaled >= 16'h1000)
            quant_idx = 4'd9;
        else if (scaled >= -16'h1000)
            quant_idx = 4'd8;
        else if (scaled >= -16'h1800)
            quant_idx = 4'd7;
        else if (scaled >= -16'h2300)
            quant_idx = 4'd6;
        else if (scaled >= -16'h3000)
            quant_idx = 4'd5;
        else if (scaled >= -16'h3500)
            quant_idx = 4'd4;
        else if (scaled >= -16'h3800)
            quant_idx = 4'd3;
        else if (scaled >= -16'h4000)
            quant_idx = 4'd2;
        else if (scaled > -16'h4200)
            quant_idx = 4'd1;
        else
            quant_idx = 4'd0;

        // Map quantized index to NF4 encoding
        nf4_out = nf4_index(quant_idx);
    end

endmodule