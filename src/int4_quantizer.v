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

    reg signed [15:0] scaled;
    reg signed [15:0] zeroed;
    reg signed [15:0] clamped;
    // NB: removed dead 'scale' LUT (scaling uses the shift below, not '*') and the
    // never-driven 'quant' reg -- both were unused leftovers (FIX 2026-06).

    always @(*) begin
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

    reg signed [3:0]  int4_signed;

    always @(*) begin
        // Sign-extend 3-bit magnitude to 4-bit signed
        if (int4_in[3])
            int4_signed = -{1'b0, int4_in[2:0]};
        else
            int4_signed = {1'b0, int4_in[2:0]};

        // Dequant: fp16_out = int4_signed << scale_exp  (R-SI-1: shift, no '*').
        // FIX (2026-06): the per-case form `{int4_signed[14:0], k'b0}` read up to 15
        // bits from the 4-bit int4_signed (out-of-range, undefined) AND the concat
        // dropped the sign. Sign-extend to 16 bits, then arithmetic-shift-left by
        // scale_exp -- correct for negative values, no out-of-range select, no '*'.
        fp16_out = {{12{int4_signed[3]}}, int4_signed} <<< scale_exp;
    end

endmodule
