# LINEUP — The TRI-NET line

> **TRI-NET** is an open, high-assurance ternary AI silicon *substrate* —
> three coordinated Tiny Tapeout chips plus one spec-to-RTL toolchain.
> It is **not** a TOPS race entry. It targets reproducibility, formal
> assurance, and ternary compute primitives that the commercial AI-edge
> stack does not natively expose.

## The four pieces

| Piece | Role | Footprint | This SKU's job in one line |
|------|------|-----------|----------------------------|
| **[tt-trinity-phi](https://github.com/gHashTag/tt-trinity-phi)**   | **φ-anchor — proof / identity chip**       | 1×1 tile      | The minimal chip that proves the rest of the line is consistent: φ²+φ⁻²=3 identity, Lucas POST, bounded-rationality anchor. |
| **[tt-trinity-euler](https://github.com/gHashTag/tt-trinity-euler)** | **e-engine — safety / control engine**     | 8×2 tiles     | Mid-size SKU that hosts the safety-control surface (SUPER-CROWN, CLARA gates, D2D). |
| **[tt-trinity-gamma](https://github.com/gHashTag/tt-trinity-gamma)** _(this repo)_ | **γ-surface — research / compute SKU**     | **8×4 tiles** | The compute / research substrate: **32-PE ternary mesh**, softmax / VSA / gradient surface, D2D mesh adapter, all 10 CLARA gap blocks. |
| **[t27](https://github.com/gHashTag/t27)** | **Spec-to-RTL toolchain + numeric-format registry** | n/a | The `.t27 → RTL → shuttle` pipeline and the canonical registry of GF / BitNet / GoldenFloat / NF4 / FP8 / Posit formats. |

Sibling shuttles are coordinated on **TTSKY26b** (SkyWater SKY130A,
[Tiny Tapeout chips](https://tinytapeout.com/chips/)) so the three chips
can be received, packaged, and bring-up'd as a triad.

## What γ-surface specifically contributes

γ is the **largest** chip of the line and the place where the actual
*compute substrate* lives.

- **8×4 γ-surface, 32-PE ternary mesh.** 8 cortical columns
  (`src/cortical_column.v`, LIF dynamics + BitNet b1.58 ternary MLP +
  GF16 dot4 input projection); 20-PE GF16 mesh (1× `trinity_quad_mesh.v`
  16 PE + 1× `trinity_mesh_2x2.v` 4 PE); plus the four columns of K3 /
  CLARA-gap surface logic — together giving the 32-PE figure quoted in
  `info.yaml`.
- **Softmax / VSA / gradient surface.** `vsa_matmul_8x8.v`,
  `vsa_matmul_16x16.v`, `gf16_popcount.v` / `gf16_popcount16.v` (VSA
  cosine / Hamming surface), `holo_lut_pe.v`, `bitnet_encoder.v`.
- **D2D / mesh.** `d2d_holo_mesh.v` (4-port N/E/S/W router,
  `uio[3:0]=TX, uio[7:4]=RX`), `trinity_mesh_2x2.v`,
  `trinity_router_2x2.v`, `trinity_quad_mesh.v`,
  `trinity_mesh_adapter_stub.v`, plus the multi-tile audit primitives
  `multi_tile_receipt.v` / `crc32_receipt.v` / `blake3_anchor.v`. The
  D2D adapter is **LAYER-FROZEN** on `w_tx` per PhD Theorem 36.1 R18 —
  see `docs/INTERCONNECT_PROTOCOL_V1.md`.
- **Five native arithmetic domains in silicon** plus the extended GF and
  quantizer family (GF4 / GF8 / GF12 / GF16 / GF20 / GF24 / GF32 / GF64 /
  GF128 / GF256; Int4 / Int8 / NF4 / FP8 E4M3 / FP8 E5M2 / Posit16). See
  `specs/numeric/*.t27` for the format registry imported from t27.
- **All 10 DARPA CLARA gap blocks** present as synthesisable RTL — see
  [`CLARA_TRACEABILITY.md`](CLARA_TRACEABILITY.md).

## Why three chips, not one

| Question | Answer |
|----------|--------|
| Why a tiny 1×1 φ chip? | So the proof / identity invariant can be re-verified independently of the larger SKUs. φ²+φ⁻²=3 is the line's anchor; you want a chip whose only job is to assert it. |
| Why an 8×2 e chip? | Mid-size substrate for the safety / control engine. Lets the assurance surface (SUPER-CROWN, CLARA gates, D2D) be evaluated without paying the area cost of the full mesh. |
| Why an 8×4 γ chip? | This is where compute lives. The 32-PE ternary mesh, VSA / softmax surface, and the full 10-gap CLARA RTL only fit at 8×4. |
| Why t27 separately? | The format registry and `.t27 → RTL` flow are reused by all three chips and by external work — versioning them in one place keeps the silicon SKUs reproducible. |

## Cross-chip invariant

All three chips assert the same **TG-TRIAD-X cross-die anchor** on the
TT output bus at reset:

```
{uio_out, uo_out} == 16'h47C0      // dot4(1,2,3,4) over GF16
```

This is the only end-to-end pin-level invariant claimed across the line.
It is verified in simulation here via `sim/tb_canonical.v` (canonical
anchor test) and gated in CI by `.github/workflows/test.yaml`
(`iverilog-canonical` job). It is **not** a substitute for measured
silicon.

## Positioning summary

| Axis | TRI-NET stance |
|------|----------------|
| Compute target | **Ternary / GF / GoldenFloat** research substrate — *not* a raw INT8/FP16 TOPS race entry. |
| PDK & RTL | **Open** — SKY130A, OpenLane2, Apache-2.0; all RTL in `src/` is reviewable. |
| Assurance | **Formal-friendly** — Coq under `coq/`, `trios-coq/`; CLARA-aligned RTL gates; reproducible `.t27 → RTL → shuttle` path. |
| Software | Research substrate; no commercial driver / compiler stack. |
| Differentiation vs Hailo / Axelera / Coral / QC AI100 / MediaTek NPU | See [`COMPETITORS.md`](COMPETITORS.md) — restrained, evidence-backed. |

## See also

- [`STATUS.md`](STATUS.md) — readiness levels and conservative gate state for this SKU
- [`CLARA_TRACEABILITY.md`](CLARA_TRACEABILITY.md) — DARPA CLARA Gap → RTL mapping
- [`BENCHMARKS.md`](BENCHMARKS.md) — three measurable demo workloads
- [`COMPETITORS.md`](COMPETITORS.md) — competitor positioning with public sources
- [Tiny Tapeout chips](https://tinytapeout.com/chips/) — shuttle catalogue (TTSKY26b)
- [DARPA CLARA](https://www.darpa.mil/research/programs/clara)
