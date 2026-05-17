// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf_formats.v
// GoldenFloat Family RTL Definitions - All 10 formats
// Based on FORMAT-SPEC-001.json v2.0
// phi^2 + phi^-2 = 3 | DOI 10.5281/zenodo.19227877

`ifndef GF_FORMATS_V
`define GF_FORMATS_V

// Wrapper module to allow Verilog-2005 localparam declarations
module gf_formats_pkg ();


// ============================================================
// GF Format Parameters (phi-optimized)
// Formula: exp = round((N-1)/phi^2), mant = N - 1 - exp
// ============================================================

// GF4: [S(1) | E(1) | M(2)] - phi_dist = 0.118
localparam GF4_BITS  = 4;
localparam GF4_EXP   = 1;
localparam GF4_MANT  = 2;
localparam GF4_BIAS = 0;

// GF8: [S(1) | E(3) | M(4)] - phi_dist = 0.132
localparam GF8_BITS  = 8;
localparam GF8_EXP   = 3;
localparam GF8_MANT  = 4;
localparam GF8_BIAS = 3;

// GF12: [S(1) | E(4) | M(7)] - BEST phi_dist = 0.047
localparam GF12_BITS  = 12;
localparam GF12_EXP   = 4;
localparam GF12_MANT  = 7;
localparam GF12_BIAS = 7;

// GF16: [S(1) | E(6) | M(9)] - PRIMARY format, phi_dist = 0.049
localparam GF16_BITS  = 16;
localparam GF16_EXP   = 6;
localparam GF16_MANT  = 9;
localparam GF16_BIAS = 31;

// GF20: [S(1) | E(7) | M(12)] - phi_dist = 0.035
localparam GF20_BITS  = 20;
localparam GF20_EXP   = 7;
localparam GF20_MANT  = 12;
localparam GF20_BIAS = 63;

// GF24: [S(1) | E(9) | M(14)] - phi_dist = 0.025
localparam GF24_BITS  = 24;
localparam GF24_EXP   = 9;
localparam GF24_MANT  = 14;
localparam GF24_BIAS = 255;

// GF32: [S(1) | E(12) | M(19)] - phi_dist = 0.014
localparam GF32_BITS  = 32;
localparam GF32_EXP   = 12;
localparam GF32_MANT  = 19;
localparam GF32_BIAS = 2047;

// GF64: [S(1) | E(24) | M(39)] - BEST phi_dist = 0.003
localparam GF64_BITS  = 64;
localparam GF64_EXP   = 24;
localparam GF64_MANT  = 39;
localparam GF64_BIAS = 8388607;

// GF128: [S(1) | E(48) | M(79)] - phi_dist = 0.010
localparam GF128_BITS  = 128;
localparam GF128_EXP   = 48;
localparam GF128_MANT  = 79;
localparam [47:0] GF128_BIAS = 48'd140737488355327;  // 2^47-1

// GF256: [S(1) | E(97) | M(158)] - phi_dist = 0.004
localparam GF256_BITS  = 256;
localparam GF256_EXP   = 97;
localparam GF256_MANT  = 158;
localparam [63:0] GF256_BIAS = 64'd0;  // 2^159-1 truncated (verilator compat)

// ============================================================
// Format Category Identifiers
// ============================================================

localparam GF_CATEGORY_GOLDENFLOAT = 3'd0;
localparam GF_CATEGORY_IEEE754    = 3'd1;
localparam GF_CATEGORY_INTEGER    = 3'd2;
localparam GF_CATEGORY_POSIT      = 3'd3;
localparam GF_CATEGORY_QUANTIZED  = 3'd4;
localparam GF_CATEGORY_BINARY     = 3'd5;

// ============================================================
// GF Format ID for routing
// ============================================================

localparam GF_ID_GF4    = 4'd0;
localparam GF_ID_GF8    = 4'd1;
localparam GF_ID_GF12   = 4'd2;
localparam GF_ID_GF16   = 4'd3;
localparam GF_ID_GF20   = 4'd4;
localparam GF_ID_GF24   = 4'd5;
localparam GF_ID_GF32   = 4'd6;
localparam GF_ID_GF64   = 4'd7;
localparam GF_ID_GF128  = 4'd8;
localparam GF_ID_GF256  = 4'd9;

localparam GF_ID_FP32   = 4'd10;
localparam GF_ID_FP16   = 4'd11;
localparam GF_ID_BF16   = 4'd12;
localparam GF_ID_FP8_E4 = 4'd13;
localparam GF_ID_FP8_E5 = 4'd14;
localparam GF_ID_INT4   = 4'd15;
localparam [4:0] GF_ID_INT8   = 5'd16;
localparam [4:0] GF_ID_NF4    = 5'd17;
localparam [4:0] GF_ID_POSIT16 = 5'd18;
localparam [4:0] GF_ID_BINARY16 = 5'd19;

// ============================================================
// Special encodings
// ============================================================

// GF16 special values (consistent across GF family)
localparam GF16_ZERO     = 16'h0000;
localparam GF16_NEG_ZERO = 16'h8000;
localparam GF16_INF_POS  = 16'h7E00;  // exp=63, mant=0
localparam GF16_INF_NEG  = 16'hFE00;  // exp=63, sign=1, mant=0
localparam GF16_NAN      = 16'hFE01;  // exp=63, sign=1, mant!=0
localparam GF16_QNAN     = 16'h7E01;  // exp=63, sign=0, mant!=0

// ============================================================
// Memory efficiency ratios vs FP32
// ============================================================

localparam GF4_MEM_RATIO_VS_FP32  = 8'd1;   // 0.125x
localparam GF8_MEM_RATIO_VS_FP32  = 8'd2;   // 0.25x
localparam GF12_MEM_RATIO_VS_FP32 = 8'd3;   // 0.375x
localparam GF16_MEM_RATIO_VS_FP32 = 8'd4;   // 0.5x
localparam GF20_MEM_RATIO_VS_FP32 = 8'd5;   // 0.625x
localparam GF24_MEM_RATIO_VS_FP32 = 8'd6;   // 0.75x
localparam GF32_MEM_RATIO_VS_FP32 = 8'd8;   // 1.0x
localparam GF64_MEM_RATIO_VS_FP32 = 8'd16;  // 2.0x
localparam GF128_MEM_RATIO_VS_FP32 = 8'd32; // 4.0x
localparam GF256_MEM_RATIO_VS_FP32 = 8'd64; // 8.0x

// ============================================================
// TOPS/W multipliers (baseline: GF16 = 55 TOPS/W)
// ============================================================

localparam GF4_TOPS_PER_W_BASE    = 8'd70;   // x1.27
localparam GF8_TOPS_PER_W_BASE    = 8'd65;   // x1.18
localparam GF12_TOPS_PER_W_BASE   = 8'd60;   // x1.09
localparam GF16_TOPS_PER_W_BASE   = 8'd55;   // baseline
localparam GF20_TOPS_PER_W_BASE   = 8'd52;   // x0.95
localparam GF24_TOPS_PER_W_BASE   = 8'd50;   // x0.91
localparam GF32_TOPS_PER_W_BASE   = 8'd48;   // x0.87
localparam GF64_TOPS_PER_W_BASE   = 8'd45;   // x0.82
localparam GF128_TOPS_PER_W_BASE  = 8'd42;   // x0.76
localparam GF256_TOPS_PER_W_BASE  = 8'd40;   // x0.73

// With AVS-48 (x1.20 boost)
localparam GF16_TOPS_PER_W_AVS48  = 8'd66;   // 55 * 1.20
localparam GF12_TOPS_PER_W_AVS48  = 8'd72;   // 60 * 1.20

// With AVS-48 + LUT-NPU (x1.44 total boost)
localparam GF16_TOPS_PER_W_MAX    = 8'd79;   // 55 * 1.44

// With AVS-96 + η≥0.93 (x5.4 total boost from baseline)
localparam GF16_TOPS_PER_W_MAX_96 = 16'd297; // 55 * 5.4

endmodule // gf_formats_pkg

`endif // GF_FORMATS_V