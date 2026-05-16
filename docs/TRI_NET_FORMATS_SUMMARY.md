# TRI-NET Format Registry — Summary

## Overview

Complete format specification for TRI-NET neural accelerator covering:
- GoldenFloat family (GF4-GF256) — phi-optimized floating point
- IEEE 754 standard formats (fp32, fp16)
- Brain Float format (bf16)
- FP8 variants (e4m3, e5m2)
- Integer quantization (int4, int8)
- Special quantization (nf4)
- Posit universal number (posit16)
- Binary format (binary16)

## GoldenFloat Family (Phi-Optimized)

| Format | Bits | Exp | Mant | Ratio | Phi Distance | Notes |
|--------|------|-----|------|-------|--------------|-------|
| GF4    | 4    | 1   | 2    | 0.500 | 0.118        | Extreme compression |
| GF8    | 8    | 3   | 4    | 0.750 | 0.132        | Weight quantization |
| GF12   | 12   | 4   | 7    | 0.571 | 0.047        | **BEST** phi approximation |
| GF16   | 16   | 6   | 9    | 0.667 | 0.049        | **PRIMARY** format, IGLA main |
| GF20   | 20   | 7   | 12   | 0.583 | 0.035        | High-precision ML training |
| GF24   | 24   | 9   | 14   | 0.643 | 0.025        | Financial calculations |
| GF32   | 32   | 12  | 19   | 0.632 | 0.014        | Near-IEEE precision |
| GF64   | 64   | 24  | 39   | 0.615 | 0.003        | **EXTENDED** scientific computing |
| GF128  | 128  | 48  | 79   | 0.608 | 0.010        | Ultra-high precision |
| GF256  | 256  | 97  | 158  | 0.614 | 0.004        | Maximum precision |

### Phi-Optimization Formula

The phi-optimal split uses:
```
exp = round((N-1)/φ²)
mant = N - 1 - exp
```

Where φ² ≈ 2.618, giving exp/mant ≈ 1/φ ≈ 0.618.

## Standard Formats

### IEEE 754 Formats

| Format | Bits | Exp | Mant | Bias | Range Notes |
|--------|------|-----|------|------|-------------|
| FP32   | 32   | 8   | 23   | 127  | IEEE 754 binary32 standard |
| FP16   | 16   | 5   | 10   | 15   | IEEE 754 binary16 standard |

### Brain Float Format

| Format | Bits | Exp | Mant | Bias | Notes |
|--------|------|-----|------|------|-------|
| BF16   | 16   | 8   | 7    | 127  | Same exp as FP32, truncated mantissa |

### FP8 Variants (OCP Specification)

| Format | Bits | Exp | Mant | Bias | Range | Use Case |
|--------|------|-----|------|------|-------|----------|
| FP8_E4M3 | 8  | 4   | 3    | 7    | [-448, 448] | Training |
| FP8_E5M2 | 8  | 5   | 2    | 15   | [-57344, 57344] | Inference |

## Integer Formats

| Format | Bits | Sign | Data | Range | Quantization Scale |
|--------|------|------|------|-------|-------------------|
| Int4   | 4    | 1    | 3    | [-8, 7] | 0.0625 |
| Int8   | 8    | 1    | 7    | [-128, 127] | 0.0039216 |

## Special Formats

### NormalFloat4 (NF4)

- 4-bit format with 16 levels drawn from Normal(0,1) quantiles
- Values: {-1.0, -0.696, -0.525, -0.394, -0.284, -0.185, -0.091, 0.0, 0.0, 0.091, 0.185, 0.284, 0.394, 0.525, 0.696, 1.0}
- Used in QLoRA for efficient 4-bit fine-tuning

### Posit16

- Type III Unum format
- Structure: [sign(1) regime(6) exp(1) mant(8)]
- Exact representation of small integers
- Gradual overflow/underflow

### Binary16

- Alias for FP16
- Separate routing class in TRI-NET

## Format Categories for Hardware Routing

```t27
pub const FormatCategory = enum(u8) {
    goldenfloat,   // GF family: phi-optimized
    ieee754,       // IEEE 754 standard formats
    integer,       // Integer quantization
    posit,         // Posit universal number format
    quantized,     // Special quantization (NF4, etc)
    binary,        // Binary formats
};
```

## Memory Efficiency vs FP32

| Format | Memory Ratio |
|--------|--------------|
| GF4    | 0.125x |
| GF8    | 0.25x |
| GF12   | 0.375x |
| GF16   | 0.5x |
| GF20   | 0.625x |
| GF24   | 0.75x |
| GF32   | 1.0x |
| GF64   | 2.0x |
| GF128  | 4.0x |
| GF256  | 8.0x |

## Files Created/Updated

### New Files
1. `/specs/numeric/tri_net_formats.t27` — Complete format registry
2. `/specs/numeric/gf256.t27` — GF256 format specification

### Updated Files
1. `/specs/numeric/goldenfloat_family.t27` — Added GF64, GF128, GF256
2. `/specs/numeric/phi_ratio.t27` — Added verification for new formats
3. `/specs/numeric/gf64.t27` — Updated to phi-optimized exp=24, mant=39
4. `/specs/numeric/gf128.t27` — Updated to phi-optimized exp=48, mant=79

## TriadNet Architecture Integration

The TRI-NET format registry enables:

1. **Hardware Format Path Selection**
   - Category-based routing for optimal silicon utilization
   - LUT-NPU optimized for GF16 (primary format)
   - Sub-V_T operation compatibility

2. **TOPS/W Multiplication Factors**
   - GF16 primary: 55 TOPS/W baseline
   - AVS-48 (η≥0.93): ~297 TOPS/W
   - LUT-NPU (×1.20): ~66 TOPS/W
   - Sub-V_T (≥350): maximum theoretical TOPS/W

3. **Memory Bandwidth Optimization**
   - Format-specific memory controllers
   - Dynamic quantization/dequantization
   - Zero-copy format conversion

## Anchor

```
φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
TRI-NET Format Registry v1.0
QUANTUM BRAIN 1:1 SILICON · PHYS→SI · BIO→SI · LANG→SI · NEVER STOP
```

## Next Steps

1. Implement format conversion hardware paths in RTL
2. Add GF64, GF128, GF256 to synthesizable RTL
3. Create hardware testbenches for all formats
4. Add format-aware memory controllers
5. Integrate with IGLA RACE system