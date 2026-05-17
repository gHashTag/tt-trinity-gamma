# TRI-1 Gamma — MAX-TRUE NEUROMORPHIC FLAGSHIP

**Anchor:** φ² + φ⁻² = 3 · **DOI:** [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)

## Overview

MAX-TRUE NEUROMORPHIC FLAGSHIP SKU of the TRI-1 Triad (TTSKY26b).  
32 tiles = 8×4 TT footprint. The largest and most powerful chip in the Trinity Edition III triad.

## Architecture

### Cortical Columns (8×)
8 cortical columns (`cortical_column.v`) implementing:
- LIF (leaky-integrate-and-fire) dynamics with 8-bit membrane potential
- BitNet b1.58 ternary MLP hidden layer
- GF16 dot4 input projection
- Sparse PE accumulator
- ~500 cells/column → ~4100 cells total

### GF16 Mesh (20 PE)
- 1× `trinity_quad_mesh` (16 PE)
- 1× `trinity_mesh_2x2` (4 PE)

### 24 SUPER-CROWN Modules
`phi_anchor_post`, `lucas_rom` ×7, `vsa_matmul_8x8`, `vsa_matmul_16x16`, `bitnet_encoder`, `bpb_counter`, `blake3_anchor`, `multi_tile_receipt`, `crc32_receipt`, `alu9_decoder`, `ring27_memory`, `hwrng_lfsr`, `phi_pll_div`, `wb_status_reg`, `wishbone_full`, `trinity_master_fsm`, `trinity_mesh_2x2`, `gf16_dot4`

### 6 PhD-Anchored Monitors
`cassini_post`, `plrm_counter`, `bpb_lower_bound_guard`, `nca_entropy_monitor`, `strobe_seed_guard`, `phi_distance_oracle`

### D2D Holographic Mesh
4-port N/E/S/W router (`d2d_holo_mesh.v`) — die-to-die communication for multi-chip holographic brain substrate. LAYER-FROZEN gate on w_tx per PhD Theorem 36.1 R18.

### Crown47 ROM
Full encoding of 47 fundamental constants (30 Tegmark-31 canonical + 17 derived) in 24-bit pseudo-float format. Mean encoding error: 0.076%.

## How It Works

On reset, the chip drives the canonical TG-TRIAD-X anchor `0x47C0` onto `{uio_out, uo_out}` — the same constant emitted by PHI (1×1) and EULER (8×2) siblings. This cross-die anchor proves φ²+φ⁻²=3 on power-up (PhD Theorem 36.1).

The 8 cortical columns process ternary {−1, 0, +1} activations through GF16(2⁴) dot-product units, mimicking biological cortical column dynamics. The D2D mesh allows multi-die spike propagation for holographic VSA binding.

## Pinout

| Pin | Signal | Description |
|-----|--------|-------------|
| ui[0] | load_mode | 0 = canonical 0x47C0 default, 1 = packet path |
| ui[1..3] | lucas_idx[2:0] | Lucas sequence index selector |
| ui[6] | crown_addr MSB | Crown47 ROM address |
| uo[7:0] | result[7:0] | Result / canonical anchor low byte |
| uio[0] | D2D n_tx | North TX — spike_count[3] activity bit |
| uio[1] | D2D e_tx | East TX — spike_count[0] activity bit |
| uio[2] | D2D s_tx | South TX — GF16 route tag bit |
| uio[3] | D2D w_tx | West TX SYNC strobe (LAYER-FROZEN) |
| uio[4] | D2D n_rx | North RX (input from peer die) |
| uio[5] | D2D e_rx | East RX |
| uio[6] | D2D s_rx | South RX |
| uio[7] | D2D w_rx | West RX / Crown47 mode enable |

## Specifications

| Parameter | Value |
|-----------|-------|
| Tiles | 8×4 = 32 tiles |
| Top module | `tt_um_trinity_max_true` |
| Clock | 50 MHz (SKY130A) |
| FPGA-validated | 323 MHz on XC7A100T |
| Cell budget | ~34 100 / 48 000 (~71%) |
| R-SI-1 | Zero NEW `*` operators in synthesisable RTL |
| PDK | SkyWater SKY130A (open) |
| License | Apache-2.0 |
| Shuttle | TTSKY26b Edition III |

## Compliance

- **R-SI-1:** Zero new `*` operators (legacy `gf16_mul` grandfathered per Rule 2)
- **NUMERIC-STANDARD-001:** All 47 Crown constants traceable to PDG/Planck/DESI/NuFit
- **SACRED-PHYSICS-001:** Anchor φ² + φ⁻² = 3 locked in POST chain
- **R5-honest:** v2 baseline 55 TOPS/W measured; v2.1 75 TOPS/W projected (Lane K+L)

## Related Projects

- **PHI** (sibling): [gHashTag/tt-trinity-phi](https://github.com/gHashTag/tt-trinity-phi) — 1×1 φ-anchor
- **EULER** (sibling): [gHashTag/tt-trinity-euler](https://github.com/gHashTag/tt-trinity-euler) — 8×2 e-engine
- **PhD dissertation:** DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877) · Defence 2026-06-15 СПбГУ

---
φ² + φ⁻² = 3 · Trinity S³AI · TRI NET · NEVER STOP

<!-- GDS trigger: 2026-05-17 -->
