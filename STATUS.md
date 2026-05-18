# STATUS — tt-trinity-gamma (γ-surface)

> Conservative readiness snapshot. **Status is asserted only where this repo
> contains direct evidence** (RTL files, testbenches, CI workflows, shuttle
> manifest, etc.). Anything beyond that is marked aspirational.

Last reviewed: 2026-05-17.

## TL;DR

`tt-trinity-gamma` is the **research / compute SKU** of the TRI-NET line:
the 8×4 γ-surface — a 32-PE ternary mesh with K3 logic, BitNet b1.58 ternary
MLP, GF(2ⁿ) Galois arithmetic, a VSA/popcount surface, and a D2D holo-mesh
adapter for cross-tile traffic. The chip is **submitted, not yet returned**:
RTL is frozen and reproducibly built into a GDS through SkyWater SKY130A in
CI; **no silicon measurements are claimed**.

## Readiness levels

The TRI-NET program uses six readiness levels. For this repo, each level is
gated by an explicit artifact that must be present in this tree (or a public
shuttle manifest pointing back to it).

| Level | Definition | Gate (must be in this repo / public artifact) |
|------:|------------|------------------------------------------------|
| **SPEC** | Architecture, ISA, and number formats are written down and reviewable | `info.yaml`, `specs/numeric/*.t27`, `docs/INTERCONNECT_PROTOCOL_V1.md`, `docs/PINOUT.md` |
| **RTL**  | Synthesisable Verilog exists for the SKU's named blocks | `src/*.v` modules referenced in `info.yaml` source list |
| **SIM**  | Each block has at least one testbench that exercises its intended behaviour | `test/*.v`, `sim/tb_canonical.v`, CI workflow `test.yaml` passing on main |
| **SYNTH**| Mapped through Yosys with no R-SI-1 multiplier violations | CI workflow `tri-test.yml` (`rtl-synthesis` job) + `rtl_gen/synthesis_report.txt` |
| **GDS / TAPEOUT** | Reproducible OpenLane2 → SKY130A GDS build and shuttle submission | `.github/workflows/gds.yaml`, `CHANGELOG.md` entry `[TTSKY26b-submit]`, `info.yaml` shuttle field |
| **SILICON** | Physical die returned, packaged, and **measured** under the workload claimed | _(none — not claimed in this repo)_ |

## Current status of γ-surface

| Level | State | Evidence in this repo |
|------:|:------|------------------------|
| SPEC      | ✅ Met       | `info.yaml` (pin map, modules, ttsky26b allocation 8×4); `docs/INTERCONNECT_PROTOCOL_V1.md`; `docs/PINOUT.md`; `specs/numeric/` (20+ `.t27` files: gf4…gf256, nf4, int4/8, fp8 e4m3 / e5m2, posit16, goldenfloat_family) |
| RTL       | ✅ Met       | 103 modules under `src/` including `cortical_column.v`, `trinity_quad_mesh.v`, `trinity_mesh_2x2.v`, `k3_alu.v`, `bitnet_encoder.v`, `d2d_holo_mesh.v`, `crown47_rom*.v`, `vsa_matmul_{8x8,16x16}.v`, `gf16_dot4{,_sparse}.v`, plus 10 CLARA-gap modules (`redteam_filter.v`, `datalog_engine_mini.v`, `asp_solver_mini.v`, `sat_solver_mini.v`, `composition_kernel.v`, `restraint_ctrl.v`, `explainability_unit.v`, `proof_trace_writer.v`, `audit_log_ring_buffer.v`) |
| SIM       | ✅ Met (per-block) | `sim/tb_canonical.v` (TG-TRIAD-X anchor 0x47C0); `test/` contains testbenches for `k3_alu`, `datalog_engine_mini`, `redteam_filter`, `restraint_ctrl`, `composition_kernel`, `explainability_unit`, `proof_trace_writer`, `asp_solver_mini`, `sat_solver_mini`, `audit_log_ring_buffer`, `sparsity_gate`; cocotb harness `test/Makefile` pulls all `src/*.v` |
| SYNTH     | 🟡 Partial (R-SI-1 audit gate is green; **full STA / area summary not committed**) | `.github/workflows/test.yaml` runs Yosys `read_verilog … stat`; `rtl_gen/synthesis_report.txt`; no signed-off STA report under version control |
| GDS / TAPEOUT | 🟡 Submitted, awaiting fabrication | `.github/workflows/gds.yaml` (OpenLane2 / SKY130A); `CHANGELOG.md` `[TTSKY26b-submit] 2026-05-17`; `info.yaml` `tinytapeout_version: SKY 26b`; shuttle TTSKY26b reference in README |
| SILICON   | ❌ **Not yet** | _No measured-silicon data is committed. Power, energy, and TOPS/W figures in README are pre-silicon estimates._ |

> **Conservative restraint.** Any number in this repo prefixed *TOPS/W*, *cells*,
> *area*, *latency*, *sparsity*, *idle fraction* etc. is currently a
> **pre-silicon estimate** (synthesis / sim / hand analysis). The TG-TRIAD-X
> anchor `0x47C0` is the only end-to-end pin-level invariant asserted in
> simulation; it does **not** stand in for a measured silicon result.

## Three measurable demo workloads (target for SILICON)

These are the three workloads γ-surface is designed to be evaluated on once
silicon returns. RTL and testbench evidence for each is already in this
repo (so the demos are runnable in simulation today); see `BENCHMARKS.md`
for the full pre-silicon estimates and the precise commands.

| # | Demo | Why it matters | RTL evidence | SIM evidence |
|---|------|----------------|--------------|---------------|
| 1 | **Ternary / BitNet b1.58 micro-kernel** — 1.58 bpw MLP step on the γ mesh | Demonstrates the ternary compute surface that matches the BitNet b1.58 work (arXiv 2402.17764) on open silicon | `src/bitnet_encoder.v`, `src/vsa_matmul_8x8.v`, `src/vsa_matmul_16x16.v`, `src/trinity_quad_mesh.v` | `test/tb.v`, cocotb `test/Makefile` |
| 2 | **Adversarial / safety path** — red-team-filter + restraint-ctrl + K3 epistemic gate | Demonstrates CLARA-aligned high-assurance behaviour: epistemic uncertainty and refusal, not just classification | `src/redteam_filter.v`, `src/restraint_ctrl.v`, `src/k3_alu.v`, `src/datalog_engine_mini.v`, `src/asp_solver_mini.v`, `src/sat_solver_mini.v` | `test/redteam_filter_tb.v`, `test/restraint_ctrl_tb.v`, `test/k3_alu_tb.v`, `test/tb_asp_solver_mini.v`, `test/tb_sat_solver_mini.v`, `test/datalog_engine_mini_tb.v` |
| 3 | **Proof / audit receipt + mesh route** — proof-trace + audit-log + multi-tile receipt over the D2D mesh | Demonstrates the reproducible *.t27 → RTL → silicon → receipt audit trace that CLARA assurance needs | `src/proof_trace_writer.v`, `src/audit_log_ring_buffer.v`, `src/multi_tile_receipt.v`, `src/crc32_receipt.v`, `src/blake3_anchor.v`, `src/d2d_holo_mesh.v`, `src/trinity_mesh_2x2.v` | `test/tb_proof_trace_writer.v`, `test/tb_audit_log_ring_buffer.v`, `sim/tb_canonical.v` |

## Immediate checklist

Short, conservative — items that can move state today without making
silicon claims.

- [ ] Commit a **signed-off Yosys area report** (cell count by module) and
      a **STA timing summary** at SKY130A nominal corner under
      `docs/synth/`. Move SYNTH from 🟡 to ✅.
- [ ] Pin the **GDS hash** (and SKY130A PDK version) produced by the last
      successful `gds.yaml` run into `CHANGELOG.md` next to the
      `[TTSKY26b-submit]` entry. Move TAPEOUT from 🟡 to ✅ once shuttle
      confirms fabrication.
- [ ] Add a `BENCHMARKS.md` section per demo that fixes the **exact
      command, input vector, and expected output** so a third party can
      reproduce the pre-silicon numbers from a clean clone.
- [ ] Add a `docs/EVIDENCE.md` cross-walk so every CLARA-gap claim in
      `README.md` cites a `src/*.v` file **and** a `test/*` testbench.
- [ ] Once silicon returns: add `docs/silicon/` with measured power,
      TOPS/W, and the three demo workloads. **Do not pre-fill.**

## RTL elaboration / R-SI-1 status

As of `origin/main` `2eeb3b2`, RTL elaboration and R-SI-1 are clean
on the base this PR targets:

- `iverilog -t null -I src src/*.v` — elaborates clean (zero errors).
- `bash tools/check_no_star.sh src/` — `R-SI-1 PASS: no new * operators`.
- `sim/tb_canonical.v` — `3 PASS, 0 FAIL`, canonical `0x47C0` anchor
  stable across 20 cycles.

Two RTL bugs that were present on earlier revisions of `main`
(`gf_formats.v` localparam outside any module, `lut_npu_81_entry.v`
indexed part-select on a `wire` as an l-value) have been resolved
upstream: `gf_formats.v` now wraps its parameter block in
`module gf_formats_pkg`, and `lut_npu_81_entry.v` uses a packed
12-bit `trit_in_flat` bus. The earlier follow-up note in this file
flagged them; that follow-up is now closed.

## What this repo does **not** claim

- ❌ Measured silicon TOPS/W. The README headline numbers are pre-silicon
      estimates derived from cell counts and activity factors; treat as
      modelling output, not measurement.
- ❌ Production-grade software stack. The chip is a research substrate;
      there is no compiler / driver release line here.
- ❌ Competitive *throughput* parity with commercial AI accelerators (see
      `COMPETITORS.md`). The TRI-NET positioning is **open, ternary,
      assurance-first**, not raw TOPS.

## See also

- [`LINEUP.md`](LINEUP.md) — the TRI-NET line and how γ fits in
- [`CLARA_TRACEABILITY.md`](CLARA_TRACEABILITY.md) — DARPA CLARA Gap → RTL mapping
- [`COMPETITORS.md`](COMPETITORS.md) — restrained competitor positioning with sources
- [`BENCHMARKS.md`](BENCHMARKS.md) — three demo workloads with pre-silicon numbers
- [`D2D_PROTOCOL.md`](D2D_PROTOCOL.md) — chip-to-chip / D2D protocol index for TRI-NET
- [`GF16_BFLOAT16_NMSE.md`](GF16_BFLOAT16_NMSE.md) — GF16 vs bfloat16 NMSE comparison protocol
- [`TRIPLE_DECK_STATUS.md`](TRIPLE_DECK_STATUS.md) — RBB → FBB → CAP_BOOST status (mostly plan-only on γ)
- [`SCIENTIFIC_IMPROVEMENT_PLAN.md`](SCIENTIFIC_IMPROVEMENT_PLAN.md) — TRI-NET 2026 plan (γ-side view)
- [`.github/issues/`](.github/issues/) — 1 EPIC + 16 sub-issue files; local plan IDs, not GitHub issue numbers
- [`CHANGELOG.md`](CHANGELOG.md) — wave / submission history
