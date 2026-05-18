# SCIENTIFIC_IMPROVEMENT_PLAN — TRI-NET 2026 (γ-surface view)

> γ-surface (this repo) is the **compute / mesh-surface chip** of TRI-NET
> (`tt-trinity-gamma`, 8×4 tiles, TT slot #4913). This plan is the
> γ-side view of the line-wide *TRI-NET 2026 Scientific Improvement
> Plan*. Sibling repos (`tt-trinity-phi`, `tt-trinity-euler`,
> [`t27`](https://github.com/gHashTag/t27)) own their own copies of the
> equivalent γ → φ / e items.
>
> **R5 honesty.** This plan contains targets, projections, and external
> references. Anything that is not already a checked-in artefact in
> this repo is marked `VERIFY`, `projection`, or `target`. Funding
> amounts, program acceptance dates, DOIs not already pinned in this
> repo, silicon return dates, paper acceptance, and headline
> TOPS-per-watt numbers from external sources are **not** asserted as
> fact here.

Last reviewed: 2026-05-18.

## Issue pack

The 16 plan items below are mirrored as markdown files under
[`.github/issues/`](.github/issues/) with the EPIC at
[`.github/issues/00_EPIC_2026.md`](.github/issues/00_EPIC_2026.md)
and per-item files `01_CL-01.md` … `16_OS-03.md`. The
[`.github/issues/ISSUES_SUMMARY.md`](.github/issues/ISSUES_SUMMARY.md)
index documents the file format and the create-script contract.

To materialise the pack as real GitHub issues, a maintainer runs
`bash .github/issues/create_issues.sh --dry-run` to preview, then
`--confirm` to create. The `#N` style numbers used in the pack are
**local plan IDs**, not GitHub issue numbers — no GitHub issue
exists for any plan item until the script is run.

## Plan-of-record

| Item ID | Track | What γ-surface ships | Status today |
|--------:|-------|----------------------|--------------|
| CL-01 | DARPA CLARA alignment | 10/10 CLARA gap blocks present as RTL | ✅ ([`CLARA_TRACEABILITY.md`](CLARA_TRACEABILITY.md)) |
| CL-02 | DARPA CLARA alignment | K3 epistemic surface + refusal-under-UNKNOWN demo | ✅ (`BENCHMARKS.md` Demo 2) |
| CL-03 | DARPA CLARA alignment | Proof-trace + audit-receipt + mesh route demo | ✅ (`BENCHMARKS.md` Demo 3) |
| CL-04 | DARPA CLARA alignment | Formal proofs under `coq/` / `trios-coq/` cross-walked to RTL | 🟡 partial |
| EN-01 | Energy efficiency | FBB-ACTIVE (0xF2) RTL lever | ✅ `src/fbb_active_path.v` |
| EN-02 | Energy efficiency | RBB (0xF1) lever | 🟡 witness-only crate, **no γ-side RTL** |
| EN-03 | Energy efficiency | CAP-BOOST (0xF3) lever | 🟡 witness-only crate, **no γ-side RTL** |
| SN-01 | SNN-TRI fusion | LIF cortical columns on the mesh | ✅ `src/cortical_column.v` |
| SN-02 | SNN-TRI fusion | BitNet b1.58 ternary MLP per column | ✅ `src/cortical_column.v`, `src/bitnet_encoder.v` |
| SN-03 | SNN-TRI fusion | GF16 vs bfloat16 falsifiable NMSE comparison | 🟡 protocol in [`GF16_BFLOAT16_NMSE.md`](GF16_BFLOAT16_NMSE.md); harness not yet committed |
| PUB-01 | Publication | TRI-NET positioning whitepaper bundle | ✅ Zenodo DOI `10.5281/zenodo.19227877` pinned in `docs/INTERCONNECT_PROTOCOL_V1.md` |
| PUB-02 | Publication | Workshop paper on the γ compute/mesh substrate | 🟡 **target** — not submitted |
| PUB-03 | Publication | Post-silicon measurement paper (TOPS/W, latency, sparsity) | ❌ gated on silicon return |
| OS-01 | Open source | Apache-2.0 RTL + open PDK (SKY130A) | ✅ `LICENSE`, `info.yaml`, `.github/workflows/gds.yaml` |
| OS-02 | Open source | Reproducible `.t27 → RTL → shuttle` flow | ✅ via [`t27`](https://github.com/gHashTag/t27); CI workflows in `.github/workflows/` |
| OS-03 | Open source | Public contributor / triage funnel (issues, CI gates) | 🟡 partial — CI is public; contributor doc not yet committed |

## 1. DARPA CLARA alignment

### CL-01 — All 10 CLARA gap blocks as synthesisable RTL

**Status:** ✅ done. See [`CLARA_TRACEABILITY.md`](CLARA_TRACEABILITY.md)
for the gap-by-gap mapping. The 10 gap-block modules
(`redteam_filter`, `datalog_engine_mini`, `asp_solver_mini`,
`sat_solver_mini`, `composition_kernel`, `restraint_ctrl`,
`explainability_unit`, `proof_trace_writer`, `audit_log_ring_buffer`,
plus `k3_alu` as the K3 epistemic surface used by Gap-2/4) are all
under `src/` and exercised by Verilog testbenches under `test/`.

**Honesty caveat.** "Gap covered by an RTL block" does not mean "Gap
formally proven". CL-04 is the gate that closes that.

### CL-02 — K3 epistemic surface + refusal demo

**Status:** ✅ done. `BENCHMARKS.md` Demo 2 wires
`redteam_filter → k3_alu → datalog/asp/sat → restraint_ctrl`. K3
truth-table coverage (TRUE / UNKNOWN / FALSE) is exercised in
`test/k3_alu_tb.v` (27/27 cases at last run).

### CL-03 — Proof-trace + audit-receipt + mesh route

**Status:** ✅ done. `BENCHMARKS.md` Demo 3 chains
`explainability_unit → composition_kernel → proof_trace_writer →
audit_log_ring_buffer → crc32_receipt → blake3_anchor →
multi_tile_receipt → d2d_holo_mesh`. The cross-die anchor `0x47C0`
gates the demo at reset (`sim/tb_canonical.v` — 3 PASS, 0 FAIL).

### CL-04 — Formal proofs cross-walked to RTL

**Status:** 🟡 partial. `coq/` and `trios-coq/` directories exist;
`src/fbb_active_path.v` header cites `FBBActive2.v`. A full
gap-by-gap proof cross-walk under `docs/EVIDENCE.md` is a
**target** — listed as an open checklist item in
[`STATUS.md`](STATUS.md). VERIFY: no DARPA CLARA acceptance,
funding, or program date is asserted by this repo.

## 2. Energy efficiency

The "triple-decker" envelope (RBB / FBB-ACTIVE / CAP-BOOST) is
detailed in [`TRIPLE_DECK_STATUS.md`](TRIPLE_DECK_STATUS.md). This
section is the planning view; the status file is the evidence view.

### EN-01 — FBB-ACTIVE (0xF2)

**Status:** ✅ RTL present. `src/fbb_active_path.v` is a 4-state FSM
with FBB level localparams 0…400 mV and a leakage-monitor input.
Witness crate `crates/fbb-active-witness/`.

**Caveat — pre-existing testbench mismatch.**
`test/tb_fbb_active_path.v` does **not** compile against the current
`src/fbb_active_path.v` at the time of this snapshot. Iverilog
reports unknown ports `enable`, `temp_mon`, `activity`, and an 8-bit
`fbb_level` connection against a 32-bit RTL port. **Not introduced by
this plan.** Closing this is a follow-up; see
[`TRIPLE_DECK_STATUS.md`](TRIPLE_DECK_STATUS.md) §2.1 and §4.

### EN-02 — RBB (0xF1)

**Status:** 🟡 witness-only. `crates/rbb-witness/` pins the parameter
band (`V_BS ≈ −2.5 mV`, leak-save band [35 %, 50 %]). **No
`src/rbb_*.v` exists in this repo.** The plan-to-close-the-gap is
spelled out in [`TRIPLE_DECK_STATUS.md`](TRIPLE_DECK_STATUS.md) §4
item 1: land `src/rbb_idle_well.v` + `test/tb_rbb_idle_well.v`.

### EN-03 — CAP-BOOST (0xF3)

**Status:** 🟡 witness-only. `crates/cap-boost-witness/` pins the
parameter band (`ΔC ≈ 0.81 pF`, di/dt margin band [4 %, 10 %]). **No
`src/cap_boost_*.v` exists in this repo.** Plan-to-close in
[`TRIPLE_DECK_STATUS.md`](TRIPLE_DECK_STATUS.md) §4 item 2: land
`src/cap_boost_rail.v` + `test/tb_cap_boost_rail.v`.

### Headline TOPS-per-watt numbers

The README cites `75 / 405` TOPS/W as **SKY130A pre-silicon
estimates** (see `README.md` and `STATUS.md`). Any larger figure that
appears in external proposals (e.g. line-wide `1000×` headline,
`4000` TOPS/W ceiling) is `VERIFY` / `projection` only — **not**
asserted by this repo, and not derivable from any artefact in this
tree without a 22FDX (or other) PDK port that has not yet landed
(see [`LINEUP.md`](LINEUP.md) §22FDX projection).

## 3. SNN-TRI fusion (Spiking Neural Networks × Ternary)

γ is the place on the line where the **SNN ↔ ternary** fusion lives:
8 cortical columns with LIF dynamics drive a 20-PE GF16 mesh that
holds BitNet b1.58 ternary weights.

### SN-01 — LIF cortical columns on the mesh

**Status:** ✅ done. `src/cortical_column.v` instantiates LIF
dynamics + BitNet MLP + GF16 dot4 input projection per column. The
local mesh is `src/trinity_quad_mesh.v` + `src/trinity_mesh_2x2.v`
(20 PE total). Eight columns × four CLARA-surface columns = the
32-PE figure quoted in `info.yaml`.

### SN-02 — BitNet b1.58 ternary MLP

**Status:** ✅ done. `src/bitnet_encoder.v` does {-1, 0, +1} → 2-bit
trit encoding. `src/vsa_matmul_8x8.v` / `src/vsa_matmul_16x16.v`
consume the trits. Demo 1 in `BENCHMARKS.md` is the runnable harness.

### SN-03 — GF16 vs bfloat16 NMSE comparison

**Status:** 🟡 protocol committed, harness not yet.
[`GF16_BFLOAT16_NMSE.md`](GF16_BFLOAT16_NMSE.md) pins the NMSE-in-dB
protocol, the input distribution (`N(0, 1)` activations × ternary
weights), the sample-count floor (≥ 10 000), and the schema for a
recorded run. The harness `tools/nmse_gf16_bf16.py` is a **target**
— not yet committed; no `Δ_dB` value is published anywhere in the
tree.

## 4. Publication path

### PUB-01 — Whitepaper / positioning bundle

**Status:** ✅ done at the line-wide level. The TRI-NET stack
provenance bundle is pinned at Zenodo DOI
[10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)
(this DOI is cited in `docs/INTERCONNECT_PROTOCOL_V1.md` and
`docs/CROSS_TILE_INTERCONNECT.md`, so it counts as repo-evidenced).
γ-side positioning is in `LINEUP.md` §Whitepaper / value proposition.

### PUB-02 — Workshop paper on the γ compute/mesh substrate

**Status:** 🟡 **target**. A workshop paper on the 8×4 γ-surface
(32-PE ternary mesh + 10 CLARA gaps + D2D routing) is on the
publication track. **No venue, deadline, or acceptance is asserted
by this repo.** Tracking lives outside this tree.

### PUB-03 — Post-silicon measurement paper

**Status:** ❌ gated. Requires SILICON readiness (currently ❌ in
[`STATUS.md`](STATUS.md)). When silicon returns, fill `docs/silicon/`
with the measured counterpart of every estimate in `BENCHMARKS.md`,
then submit. No date is claimed.

## 5. Open-source community

### OS-01 — Apache-2.0 + open PDK

**Status:** ✅ done. `LICENSE` is Apache-2.0; `info.yaml` declares
SKY130A; `.github/workflows/gds.yaml` runs OpenLane2 → SKY130A in CI.

### OS-02 — Reproducible `.t27 → RTL → shuttle` flow

**Status:** ✅ done. Format registry under `specs/numeric/*.t27` is
mirrored from [`t27`](https://github.com/gHashTag/t27). CI workflows
exercise the flow on every push.

### OS-03 — Contributor / triage funnel

**Status:** 🟡 partial. CI is public and gates `iverilog` elaboration
+ R-SI-1 + canonical anchor. Contributor doc (`CONTRIBUTING.md`,
triage labels, RFC template) is **not yet committed** — listed as a
follow-up.

## 6. Timeline (γ-side, plan-only — no calendar dates asserted)

The line-wide programme calendar is owned outside this repo. γ-side
ordering of work, expressed as sequencing rather than dates:

1. **Now → next wave.** Land NMSE harness (SN-03), repair
   `tb_fbb_active_path.v` (EN-01 caveat).
2. **After that.** Land `src/rbb_idle_well.v` and
   `src/cap_boost_rail.v` (EN-02, EN-03). These change the GDS hash
   and would be a new shuttle submission.
3. **Gated on silicon return.** Fill `docs/silicon/` with measured
   power, energy, TOPS/W, three demo workloads. Move SILICON gate
   from ❌ to ✅ in `STATUS.md`. Submit PUB-03.
4. **Parallel.** Land `docs/EVIDENCE.md` for CL-04 (formal cross-walk).
   Land `CONTRIBUTING.md` for OS-03.

VERIFY: no calendar date, programme deadline, or funding deliverable
date is claimed by this repo.

## 7. Success metrics (γ-side)

Each metric is paired with the artefact whose existence (or measured
value, post-silicon) decides whether the metric is met. **No metric
in this section is claimed met today unless the artefact column says
✅.**

| Metric | Target (γ-side) | Decided by | Status |
|--------|-----------------|------------|--------|
| All 10 CLARA gaps as RTL | 10/10 | `CLARA_TRACEABILITY.md` | ✅ |
| Canonical anchor stable in sim | `{uio_out, uo_out} = 0x47C0` | `sim/tb_canonical.v` | ✅ (3 PASS, 0 FAIL) |
| R-SI-1 (`*` audit) | no new `*` operators | `tools/check_no_star.sh` | ✅ |
| Triple-Deck levers in γ-side RTL | 3 / 3 | `src/fbb_active_path.v`, `src/rbb_*.v`, `src/cap_boost_*.v` | 🟡 1 / 3 |
| GF16 vs bfloat16 `Δ_dB` published | ≤ 0 dB on BitNet b1.58 | `docs/measurements/nmse_<date>.json` | 🟡 protocol only |
| Coq proofs cross-walked to RTL | 10/10 CLARA gaps | `docs/EVIDENCE.md` | 🟡 not committed |
| Measured silicon TOPS/W | _target only_ | `docs/silicon/` | ❌ gated on silicon return |
| Workshop paper submitted | 1 venue | external tracker | 🟡 target only |

## 8. References

Repo-internal:

- [`STATUS.md`](STATUS.md) — readiness gates (SPEC / RTL / SIM / SYNTH / GDS / SILICON)
- [`LINEUP.md`](LINEUP.md) — TRI-NET line, TRI-NET API, whitepaper, 22FDX projection
- [`BENCHMARKS.md`](BENCHMARKS.md) — three measurable demo workloads
- [`CLARA_TRACEABILITY.md`](CLARA_TRACEABILITY.md) — CLARA Gap → RTL
- [`D2D_PROTOCOL.md`](D2D_PROTOCOL.md) — chip-to-chip protocol index
- [`GF16_BFLOAT16_NMSE.md`](GF16_BFLOAT16_NMSE.md) — NMSE comparison protocol
- [`TRIPLE_DECK_STATUS.md`](TRIPLE_DECK_STATUS.md) — RBB → FBB → CAP_BOOST status
- [`COMPETITORS.md`](COMPETITORS.md) — restrained competitor positioning
- `docs/INTERCONNECT_PROTOCOL_V1.md` — TIP v1.0 wire spec
- `docs/CROSS_TILE_INTERCONNECT.md` — TTSKY26b DevKit role assignment
- `docs/TRI_NET_DARPA_CLARA_PROPOSAL.md` — line-wide CLARA proposal text

External (cited as `VERIFY` where this repo holds no artefact):

- [DARPA CLARA programme](https://www.darpa.mil/research/programs/clara) — programme exists; **no claim of acceptance, award, or schedule by TRI-NET is asserted here**.
- [BitNet b1.58 (arXiv:2402.17764)](https://arxiv.org/abs/2402.17764) — referenced format.
- [Tiny Tapeout chips](https://tinytapeout.com/chips/) — shuttle catalogue (TTSKY26b).
- [Zenodo DOI 10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877) — pinned in `docs/INTERCONNECT_PROTOCOL_V1.md`. Any *additional* DOI mentioned in the line-wide plan is `VERIFY` until it lands in a repo artefact.
- [`t27` toolchain](https://github.com/gHashTag/t27) — sibling repo, owns numeric-format registry.
- Sibling chip repos — [`tt-trinity-phi`](https://github.com/gHashTag/tt-trinity-phi), [`tt-trinity-euler`](https://github.com/gHashTag/tt-trinity-euler). Their copies of this plan are authoritative for the phi/e-side items.

## 9. R5 honesty — what this plan does **not** claim

- ❌ DARPA CLARA acceptance, award, or funding amount.
- ❌ Programme calendar dates, milestone dates, or paper-acceptance dates.
- ❌ Silicon return date or measured TOPS/W. README headline `75 / 405` TOPS/W remain SKY130A pre-silicon estimates per [`STATUS.md`](STATUS.md).
- ❌ External `1000×` energy-efficiency claim or `4000` TOPS/W ceiling as a γ-side fact. These appear in line-wide planning material but are not derivable from a checked-in γ-side artefact; treated as `projection` only.
- ❌ DOIs other than the one already pinned in `docs/INTERCONNECT_PROTOCOL_V1.md`. Any new DOI would be a new release artefact.
- ❌ RBB / CAP-BOOST RTL on γ. Both remain witness-only crates (see [`TRIPLE_DECK_STATUS.md`](TRIPLE_DECK_STATUS.md)).
- ❌ A fixed FBB-ACTIVE testbench. The pre-existing
  `test/tb_fbb_active_path.v` port mismatch is honestly recorded;
  repairing it is a follow-up, not in scope here.
