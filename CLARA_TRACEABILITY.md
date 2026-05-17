# CLARA Traceability — tt-trinity-gamma

> **DARPA CLARA** — Critical Logic Assurance for Reasoning AI — defines a
> set of capability "gaps" that current AI accelerators do not natively
> address (epistemic uncertainty, deductive reasoning, refusal,
> auditability, etc.). Program page:
> <https://www.darpa.mil/research/programs/clara>.
>
> This file is the **traceability matrix** from each CLARA gap to the RTL
> file in this repo that implements the gap and the testbench that
> exercises it. The mapping is intentionally **conservative**: every row
> cites a real file under `src/` and (where present) `test/`.

Last reviewed: 2026-05-17 against `7a66c78` (main).

## Why this file exists

γ-surface is the only TRI-NET SKU that hosts the **full 10-gap CLARA
RTL surface** in a single die (`info.yaml` allocation 8×4). The
`tt-trinity-euler` SKU hosts a subset and the `tt-trinity-phi` SKU hosts
the anchor only. This matrix lets a reviewer go from CLARA terminology
→ this codebase without first reading the entire README.

## CLARA gap → RTL → testbench

| CLARA gap | Capability | RTL (`src/`) | Testbench (`test/` or `sim/`) | Conservative status |
|----------:|------------|--------------|--------------------------------|----------------------|
| **Gap-1** | Adversarial / red-team input filtering | [`redteam_filter.v`](src/redteam_filter.v) | [`redteam_filter_tb.v`](test/redteam_filter_tb.v) | RTL + SIM present |
| **Gap-2** | **Native K3 (Kleene three-valued) logic** in silicon — epistemic uncertainty as a first-class value | [`k3_alu.v`](src/k3_alu.v) | [`k3_alu_tb.v`](test/k3_alu_tb.v) | RTL + SIM present |
| **Gap-3** | Datalog-style deductive inference | [`datalog_engine_mini.v`](src/datalog_engine_mini.v) | [`datalog_engine_mini_tb.v`](test/datalog_engine_mini_tb.v) | RTL + SIM present |
| **Gap-4** | Bounded rationality / refusal / restraint control | [`restraint_ctrl.v`](src/restraint_ctrl.v) | [`restraint_ctrl_tb.v`](test/restraint_ctrl_tb.v) | RTL + SIM present |
| **Gap-5** | Explainability / decision attribution | [`explainability_unit.v`](src/explainability_unit.v) | [`tb_explainability_unit.v`](test/tb_explainability_unit.v) | RTL + SIM present |
| **Gap-6** | Answer-set programming / non-monotonic reasoning | [`asp_solver_mini.v`](src/asp_solver_mini.v) | [`tb_asp_solver_mini.v`](test/tb_asp_solver_mini.v) | RTL + SIM present |
| **Gap-7** | Compositional kernel — combine sub-decisions under constraint | [`composition_kernel.v`](src/composition_kernel.v) | [`tb_composition_kernel.v`](test/tb_composition_kernel.v) | RTL + SIM present |
| **Gap-8** | Proof-trace writer — emit machine-checkable evidence per decision | [`proof_trace_writer.v`](src/proof_trace_writer.v) | [`tb_proof_trace_writer.v`](test/tb_proof_trace_writer.v) | RTL + SIM present |
| **Gap-9** | SAT-solver-backed consistency check | [`sat_solver_mini.v`](src/sat_solver_mini.v) | [`tb_sat_solver_mini.v`](test/tb_sat_solver_mini.v) | RTL + SIM present |
| **Gap-10** | Audit log ring buffer — tamper-evident decision history | [`audit_log_ring_buffer.v`](src/audit_log_ring_buffer.v) | [`tb_audit_log_ring_buffer.v`](test/tb_audit_log_ring_buffer.v) | RTL + SIM present |

> **"Status" disclaimer.** "RTL + SIM present" means the file exists in
> this tree and has a testbench compiled by the CI workflows
> [`test.yaml`](.github/workflows/test.yaml) and
> [`tri-test.yml`](.github/workflows/tri-test.yml). It does **not** mean
> formal proof of the CLARA capability, and it does **not** mean measured
> silicon. See [`STATUS.md`](STATUS.md) for the readiness ladder.

## Supporting assurance surface

Beyond the 10 gap blocks, γ-surface carries assurance primitives the
gap blocks rely on. These are the audit / proof / cross-tile pieces
that make a CLARA-style trace reproducible:

| Capability | RTL | Notes |
|------------|-----|-------|
| CRC32 decision receipt | `src/crc32_receipt.v` | Per-decision integrity tag |
| BLAKE3 anchor | `src/blake3_anchor.v` | Long-horizon audit anchor |
| Multi-tile receipt | `src/multi_tile_receipt.v` | Cross-tile decision binding |
| D2D holo mesh router | `src/d2d_holo_mesh.v` | 4-port N/E/S/W cross-tile transport; LAYER-FROZEN `w_tx` per PhD Thm 36.1 R18 |
| Canonical pin anchor (TG-TRIAD-X) | `sim/tb_canonical.v` | Asserts `{uio_out,uo_out} == 16'h47C0` end-to-end |
| Proof manifest (Coq / Rocq provenance) | `docs/CLARA_PROOF_MANIFEST.md` | Maps RTL to formal proof obligations |
| Interconnect protocol freeze | `docs/INTERCONNECT_PROTOCOL_V1.md` | Frozen at TTSKY26b |

## How this maps to the three demo workloads

The three measurable workloads in [`BENCHMARKS.md`](BENCHMARKS.md) are
chosen so that **each one exercises a distinct slice of the CLARA gap
surface**:

1. **Ternary / BitNet b1.58 micro-kernel** — compute-substrate demo.
   Cuts across the mesh and ternary surface; touches Gap-2 (K3 valid /
   invalid encoding) at the input boundary.
2. **Adversarial / safety path** — Gap-1 → Gap-2 → Gap-3 → Gap-4 →
   Gap-6 → Gap-9 chain. Demonstrates that a hostile input can be
   filtered, evaluated under K3 ("I don't know" is a value), reasoned
   over, and refused — instead of silently misclassified.
3. **Proof / audit receipt + mesh route** — Gap-5 → Gap-7 → Gap-8 →
   Gap-10 chain over the D2D mesh. Demonstrates that the line emits a
   machine-checkable per-decision trace and binds it across tiles.

## What is **not** claimed

- ❌ This file does not claim that any RTL block is formally proven to
      meet a CLARA gap. The Coq trees under `coq/` and `trios-coq/` are
      where proof obligations live; not every obligation is closed.
- ❌ This file does not claim measured silicon. All evidence is RTL +
      simulation + CI as of the commit above.
- ❌ This file does not claim DARPA endorsement. CLARA is referenced as
      the public capability framework these blocks are designed to map
      onto, per the program page linked above.

## Sources

- DARPA CLARA program — <https://www.darpa.mil/research/programs/clara>
- `docs/CLARA_PROOF_MANIFEST.md` — Coq / Rocq provenance manifest in this tree
- `docs/TRI_NET_DARPA_CLARA_PROPOSAL.md` — TRI-NET proposal alignment
