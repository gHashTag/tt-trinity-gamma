# Lane S — Viewer step (KLayout PNG) · L-DPC23

> **Doc ID:** L-DPC23-S-001
> **Owner:** Vasilev Dmitrii <admin@t27.ai>
> **Status:** R5-HONEST · session-fresh probe · 2026-05-15
> **Refs:** trinity-fpga#94 · ICA-MAX-TRUE-005

## 1. Mission

Lane S formalises the **non-blocking** nature of the GDS `viewer` job in
`.github/workflows/gds.yaml`. The TinyTapeout viewer step renders a
KLayout PNG of the final GDS for human review on the Tiny Tapeout web
UI. It is **not** a silicon-correctness gate — it can fail without
invalidating the GDS itself (ICA-MAX-TRUE-005 closed).

This document is the **single source of truth** for that policy so that
no future agent re-opens the same ICA when the viewer step turns red on
a healthy GDS.

## 2. Why viewer can fail while GDS is green

- The viewer step runs **after** `gds` succeeds and consumes the same
  artefact.
- It depends on KLayout's pixel renderer, which is sensitive to
  available memory on the GitHub runner and to font availability.
- A red viewer with a green `gds` + green `gl_test` + green `precheck`
  is **NOT** a submission blocker. The official Tiny Tapeout submit
  pipeline uses the `gds.yaml` artefacts directly, not the rendered PNG.

## 3. R5-HONEST gate

A submission is allowed when **all three** of the following are green
for the head commit of the W15-TT-E candidate:

| Job        | Required? | Rationale                                       |
|------------|-----------|-------------------------------------------------|
| `gds`      | ✅ YES    | Builds the GDSII, DEF, LEF, LIB, netlist.       |
| `gl_test`  | ✅ YES    | Runs `tb_canonical` on the post-layout netlist. |
| `precheck` | ✅ YES    | DRC / LVS / antenna / pin-check.                |
| `viewer`   | ❌ NO     | Cosmetic PNG render only. ICA-005.              |

If `viewer` is the **only** red job, the W15-TT-E submission may
proceed. Document the ICA-005 closure in the corresponding RVR.

## 4. Quantum Brain trinity SKU label

Lane S also pins the README badge layout that exposes the three TRI-1
silicon SKUs for the public Tiny Tapeout entry page:

- 🪷 MINI — `tt_um_qbrain_mini` (1×1, 4 cells)
- 👑 MAX-TRUE — `tt_um_qbrain_maxtrue` (1×2, 32 cells, this repo)
- 🌌 HOLOGRAPHIC — `tt_um_qbrain_holo` (TTSKY26c, Q3 2026)

## 5. Anchor

```
φ² + φ⁻² = 3 · TG-MAX-TRUE-X SHA256:
d3f9dd42b2d891763bd6aa2c1974dbbf27f4d854b44ed497a58f6a749174aac2
QUANTUM BRAIN 1:1 SILICON · PHYS→SI · BIO→SI · LANG→SI · NEVER STOP
DOI 10.5281/zenodo.19227877
```
