# GF16 vs bfloat16 — NMSE Comparison Protocol

> Standard, falsifiable protocol for comparing **GoldenFloat-16 (GF16)** —
> γ-surface's primary 16-bit numeric format — against the
> industry-standard **bfloat16** at workload-level, using Normalised Mean
> Squared Error (NMSE) as the figure of merit.
>
> This document is a **harness specification**, not a result page.
> Measured NMSE numbers are filed under `docs/silicon/` only after a
> measurement run that follows this protocol. No silicon numbers are
> pre-filled.

Last reviewed: 2026-05-18.

## 1. Motivation

γ-surface stores activations and weights in **GF16** (1 sign / 6 exp /
9 mantissa, bias 31 — see `specs/numeric/gf16.t27`). The industry
default for ML accelerators is **bfloat16** (1/8/7). The two formats
trade exponent range against mantissa precision in opposite directions,
so the only meaningful comparison is **end-to-end NMSE on the
workload**, not a synthetic per-format histogram.

This file pins the comparison protocol so a reviewer can reproduce it
from a clean clone and so future measurements can be compared
across waves of the t27 toolchain.

## 2. Formats under test

| Format | Bits | Sign / Exp / Mant | Bias | Source in repo |
|--------|-----:|-------------------|-----:|----------------|
| **GF16** (γ-surface primary) | 16 | 1 / 6 / 9 | 31 | `specs/numeric/gf16.t27`, `src/gf16_*.v` |
| **bfloat16** (reference) | 16 | 1 / 8 / 7 | 127 | `specs/numeric/formats.t27` (`bf16` enum), industry standard |
| **fp16 / binary16** (secondary reference) | 16 | 1 / 5 / 10 | 15 | `specs/numeric/binary16.t27`, `src/gf16_to_fp16.v` |

GF16 ↔ fp16 conversion is implemented in `src/gf16_to_fp16.v`. There is
currently **no** GF16 ↔ bfloat16 hardware path; the bfloat16 reference
is computed off-chip in the harness host.

## 3. NMSE — definition

For a workload that produces a reference vector `y_ref` (computed in
fp64 with the same algorithm) and a candidate vector `y_fmt` (computed
in the format under test), define

```
NMSE(y_fmt) = sum_i (y_fmt[i] - y_ref[i])^2  /  sum_i y_ref[i]^2
```

Report NMSE as **dB**: `NMSE_dB = 10 * log10(NMSE)`. More negative is
better. The protocol records:

1. `NMSE_GF16_dB`
2. `NMSE_bf16_dB`
3. `Δ_dB = NMSE_GF16_dB − NMSE_bf16_dB` (positive → GF16 is worse;
   negative → GF16 is better)

A claim that "GF16 is competitive with bfloat16 at workload W" requires
`Δ_dB ≤ +0` over the workload's input distribution, with the
distribution and sample count both fixed (§5).

## 4. Workloads (γ-side)

The three workloads in [`BENCHMARKS.md`](BENCHMARKS.md) are the targets:

| # | Workload | γ RTL under test | Why NMSE applies |
|---|----------|------------------|-------------------|
| 1 | BitNet b1.58 micro-kernel | `src/cortical_column.v`, `src/vsa_matmul_8x8.v`, `src/vsa_matmul_16x16.v`, `src/bitnet_encoder.v` | The MLP output is a numeric vector; bf16 is the typical training format for the same architecture. |
| 2 | Adversarial / safety path | `src/k3_alu.v`, `src/redteam_filter.v`, … | K3 surface is *not* a numeric vector — NMSE **does not apply**. Reported as N/A. |
| 3 | Receipt / mesh route | `src/multi_tile_receipt.v`, `src/d2d_holo_mesh.v`, … | Receipt is a hash — exact match required. NMSE **does not apply**. |

Only Workload 1 produces NMSE numbers under this protocol. Demos 2 and
3 use their own pass/fail rules (see `BENCHMARKS.md`).

## 5. Input distribution and sample count

To be considered a comparison run (not a spot check), every NMSE
measurement must declare:

| Knob | Required value (minimum) | Notes |
|------|--------------------------|-------|
| Input distribution | `N(0, 1)` activations, ternary weights drawn uniformly from `{-1, 0, +1}` | Matches BitNet b1.58. |
| Sample count | ≥ 10 000 dot-product evaluations | Lower bound for stable NMSE. |
| Reference precision | fp64 reduction of the same bit-exact algorithm | No fused MAC tricks. |
| Seed | recorded in the run log | For reproducibility. |
| Toolchain | `git rev-parse HEAD` and t27 release tag | Tie NMSE to a specific RTL hash. |

Lower sample counts or undeclared distributions invalidate the
comparison — they may not be published as NMSE numbers under this
protocol.

## 6. Reproduction harness (skeleton)

The harness lives at `tools/nmse_gf16_bf16.py` — **not yet checked
in**; this section is the spec. Pull request welcome (see Issue
template in §9).

```bash
# Prerequisites
pip install numpy

# Run harness (when implemented):
python tools/nmse_gf16_bf16.py \
    --workload bitnet_b158 \
    --samples 10000 \
    --seed 0 \
    --rtl-hash $(git rev-parse HEAD) \
    --out docs/measurements/nmse_$(date +%Y%m%d).json
```

Expected output (schema):

```json
{
  "workload": "bitnet_b158",
  "samples": 10000,
  "seed": 0,
  "rtl_hash": "<sha>",
  "nmse_gf16_db": -XX.X,
  "nmse_bf16_db": -YY.Y,
  "delta_db": <gf16 - bf16>,
  "verdict": "GF16-competitive | GF16-worse | INVALID"
}
```

Until the harness is committed, **no `Δ_dB` value may be published**
in `README.md`, `BENCHMARKS.md`, or any release note.

## 7. Link to the t27 protocol

The format registry lives in
[`t27`](https://github.com/gHashTag/t27) and is mirrored here under
`specs/numeric/`. GF16 is the **primary** format in the registry; bf16
is named as an IEEE FP reference (`specs/numeric/formats.t27` line ~115
`fp16, bf16, fp8_e4m3, fp8_e5m2`). Any NMSE run under this protocol
must cite the `t27` release tag whose registry entry was used.

## 8. R5 honesty — what is plan-only

- The harness `tools/nmse_gf16_bf16.py` is **planned**. This file
  specifies it; the script is not yet in the tree.
- No NMSE numbers are claimed in this file. The tables in §5–§6 are
  schemas, not measurements.
- `src/gf16_to_fp16.v` exists; there is **no** `src/gf16_to_bf16.v` in
  this repo. bf16 reference is computed in host fp64 in the harness.
- Workload 1 (BitNet b1.58) is currently evaluated qualitatively in
  `BENCHMARKS.md` — NMSE binding is a strict superset of that demo.

## 9. Acceptance / issue checklist

To close this out and publish a real `Δ_dB`:

- [ ] Commit `tools/nmse_gf16_bf16.py` implementing the schema in §6.
- [ ] Wire a CI smoke run (small sample count) into `.github/workflows/test.yaml`.
- [ ] First measured `docs/measurements/nmse_<date>.json` produced from
      a clean clone.
- [ ] Cross-link from `BENCHMARKS.md` Demo 1.
- [ ] `t27` release tag pinned alongside `rtl_hash`.

## See also

- [`BENCHMARKS.md`](BENCHMARKS.md) — workload runtimes and pre-silicon estimates
- [`STATUS.md`](STATUS.md) — readiness levels (SILICON still gated)
- [`specs/numeric/gf16.t27`](specs/numeric/gf16.t27) — GF16 format
- [`specs/numeric/formats.t27`](specs/numeric/formats.t27) — full registry
- [`t27`](https://github.com/gHashTag/t27) — spec-to-RTL toolchain
