// SPDX-License-Identifier: Apache-2.0
// tt-trinity-gamma/src/gfternary_to_fp32.v
// GFTernary (2-bit literal ternary float) <-> IEEE-754 FP32.
//
// GFTernary is the atomic substrate of the GoldenFloat ladder: a 2-bit code
// representing {0, +phi, -phi} EXACTLY, with phi = (1 + sqrt 5) / 2 fixed
// (cf. TWN / BitNet b1.58 where the scale alpha is learned).
//
//   code   value      fp32
//   00     0          0x00000000
//   01     +phi       0x3FCF1BBD   (1.6180339887...)
//   10     -phi       0xBFCF1BBD
//   11     reserved   -> qNaN (0x7FC00000)
//
// Status: [Spec] (derived from the GoldenFloat family doc; no separate
// gfternary.t27 SSOT exists yet, so this RTL is the reference encoding).

`default_nettype none

// ---------------------------------------------------------------------------
// Decode: 2-bit GFTernary -> FP32
// ---------------------------------------------------------------------------
module gfternary_to_fp32 (
    input  wire [1:0]  gft_in,
    output reg  [31:0] fp_out
);
    localparam [31:0] FP_PHI_POS = 32'h3FCF1BBD;  // +phi
    localparam [31:0] FP_PHI_NEG = 32'hBFCF1BBD;  // -phi
    localparam [31:0] FP_ZERO    = 32'h00000000;
    localparam [31:0] FP_QNAN    = 32'h7FC00000;

    always @(*) begin
        case (gft_in)
            2'b00: fp_out = FP_ZERO;
            2'b01: fp_out = FP_PHI_POS;
            2'b10: fp_out = FP_PHI_NEG;
            2'b11: fp_out = FP_QNAN;   // reserved code
        endcase
    end
endmodule

// ---------------------------------------------------------------------------
// Encode: FP32 -> nearest GFTernary code.
// Nearest of {0, +phi, -phi}; the magnitude boundary is phi/2 ~= 0.809
// (|x| < phi/2 -> 0, else +/-phi by sign). NaN/Inf -> reserved (11).
// FP32 magnitude is monotonic in its low 31 bits, so a single unsigned
// compare against |phi/2| suffices.
// ---------------------------------------------------------------------------
module fp32_to_gfternary (
    input  wire [31:0] fp_in,
    output reg  [1:0]  gft_out
);
    localparam [30:0] FP_HALF_PHI = 31'h3F4F1BBD;  // |phi/2| = 0.80901699...

    wire        sign = fp_in[31];
    wire [30:0] mag  = fp_in[30:0];
    wire [7:0]  exp  = fp_in[30:23];
    wire [22:0] man  = fp_in[22:0];
    wire        is_nan_inf = (exp == 8'hFF);  // Inf or NaN -> reserved

    always @(*) begin
        if (is_nan_inf)
            gft_out = 2'b11;                       // reserved
        else if (mag < FP_HALF_PHI)
            gft_out = 2'b00;                       // round to 0
        else
            gft_out = sign ? 2'b10 : 2'b01;        // -phi / +phi
    end

    wire _unused = &{1'b0, man};
endmodule
