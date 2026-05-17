# BENCHMARKS — Three measurable demo workloads

> Three workloads γ-surface is designed to be evaluated on. **All numbers
> below are pre-silicon (synthesis / sim / hand analysis).** They are
> committed here so a reviewer can reproduce them from a clean clone
> and, when silicon returns, compare them against measured results.

Last reviewed: 2026-05-17.

## Ground rules

- **No silicon measurements are claimed.** Anything labelled
  "estimate" comes from cell count × activity factor × SKY130A library
  data, not from a returned die. See [`STATUS.md`](STATUS.md).
- **All three demos are runnable today** under iverilog / cocotb via
  the workflows in [`.github/workflows/`](.github/workflows/).
- **TG-TRIAD-X anchor.** Every reset sequence must emit
  `{uio_out, uo_out} == 16'h47C0` per `sim/tb_canonical.v`. A demo that
  doesn't pass the canonical anchor test is not allowed to publish
  numbers from this file.

## Reproduction harness (shared)

```bash
# Prerequisites
sudo apt-get install -y iverilog yosys
pip install cocotb

# Canonical anchor test — gates everything below
cd sim
iverilog -o /tmp/tb_canonical -I../src ../src/*.v tb_canonical.v
vvp /tmp/tb_canonical
# Expect: TG-TRIAD-X anchor 0x47C0 observed at reset

# Cocotb full RTL suite
cd ../test
make SIM=icarus
```

The same flow is exercised in CI by [`test.yaml`](.github/workflows/test.yaml)
(`iverilog-canonical` and `cocotb-rtl` jobs).

---

## Demo 1 — Ternary / BitNet b1.58 micro-kernel

**What it shows.** That γ-surface natively executes the ternary MLP
weight format from [BitNet b1.58](https://arxiv.org/abs/2402.17764) as a
silicon primitive, not as a quantization mode in a compiler.

**RTL under test.**

- `src/bitnet_encoder.v` — encodes {-1, 0, +1} weights into the 2-bit
  trit format.
- `src/vsa_matmul_8x8.v`, `src/vsa_matmul_16x16.v` — the VSA / popcount
  surface that consumes the trit weights.
- `src/trinity_quad_mesh.v`, `src/trinity_mesh_2x2.v` — the 20-PE GF16
  mesh that holds the cortical-column activations.
- `src/cortical_column.v` — LIF + BitNet b1.58 MLP per column.

**Run.**

```bash
cd test
make SIM=icarus MODULE=test
# Cocotb sweeps tt_um_trinity_max_true with BitNet-shaped weight inputs;
# see test/test.py + test/tb.v.
```

**Pre-silicon target.**

| Metric | Pre-silicon estimate | Source |
|--------|----------------------|--------|
| Weight density | **1.58 bpw** (log₂ 3) | BitNet b1.58 paper |
| MAC primitive | XOR + popcount (no `*` operator) | Yosys `$mul` audit gate in `test.yaml` |
| Compression vs INT8 | **5.04×** | README Number Formats §4 |
| Compression vs FP16 | **10.1×** | README Number Formats §4 |
| Effective ops/cycle at 74.3% sparsity (`gf16_dot4_sparse`) | **3.83 ops/cycle** vs 1.0 dense | README §5 |

**What this is *not*.** A silicon TOPS/W claim. The 75 / 405 TOPS/W
numbers in the README and `info.yaml` are *baseline / AVS-96* modelling
estimates from synthesis activity factors — they are committed for
falsifiability but not yet measured.

---

## Demo 2 — Adversarial / safety path

**What it shows.** That an input flagged as adversarial flows through
the CLARA gap surface and ends in **refusal under epistemic
uncertainty**, rather than silently being classified.

**Pipeline under test (in input order).**

1. `src/redteam_filter.v` (CLARA Gap-1) — flags hostile input.
2. `src/k3_alu.v` (CLARA Gap-2) — represents the result as a K3 value:
   `TRUE / UNKNOWN / FALSE` instead of a boolean.
3. `src/datalog_engine_mini.v` (Gap-3) — runs the input through a
   datalog rule set.
4. `src/asp_solver_mini.v` (Gap-6) and `src/sat_solver_mini.v` (Gap-9)
   — non-monotonic / SAT consistency checks.
5. `src/restraint_ctrl.v` (Gap-4) — refuses when the K3 result is
   `UNKNOWN` or any solver returns inconsistent.

**RTL evidence.** Every file above is referenced in
[`CLARA_TRACEABILITY.md`](CLARA_TRACEABILITY.md) with its testbench.

**Run.**

```bash
cd test
iverilog -o /tmp/tb_redteam ../src/*.v redteam_filter_tb.v
vvp /tmp/tb_redteam

iverilog -o /tmp/tb_k3 ../src/k3_alu.v k3_alu_tb.v
vvp /tmp/tb_k3

iverilog -o /tmp/tb_restraint ../src/*.v restraint_ctrl_tb.v
vvp /tmp/tb_restraint

iverilog -o /tmp/tb_asp ../src/*.v tb_asp_solver_mini.v
vvp /tmp/tb_asp

iverilog -o /tmp/tb_sat ../src/*.v tb_sat_solver_mini.v
vvp /tmp/tb_sat
```

**Pre-silicon target.**

| Metric | Pre-silicon target | Notes |
|--------|---------------------|-------|
| K3 value coverage in test | 3/3 (TRUE / UNKNOWN / FALSE all exercised) | `test/k3_alu_tb.v` covers AND, OR, NOT truth tables |
| Refusal under `UNKNOWN` | observed on at least one path | `restraint_ctrl_tb.v` |
| Adversarial input flagged | ≥1 distinct red-team pattern | `redteam_filter_tb.v` |
| Solver consistency check | ASP + SAT both reachable from filter output | `tb_asp_solver_mini.v`, `tb_sat_solver_mini.v` |

**Falsification rule.** If a classical-2-valued boolean reduction of
the path silently outputs a confident class on adversarial input that
the K3 path refuses, this demo *fails* — that is the entire point of
CLARA Gap-2 + Gap-4.

---

## Demo 3 — Proof / audit receipt + mesh route

**What it shows.** That a decision made on one tile produces a
**machine-checkable receipt** and that the receipt survives a mesh
route to a sibling tile.

**Pipeline under test.**

1. `src/explainability_unit.v` (Gap-5) — attribution for the decision.
2. `src/composition_kernel.v` (Gap-7) — combines sub-decisions.
3. `src/proof_trace_writer.v` (Gap-8) — emits the proof trace.
4. `src/audit_log_ring_buffer.v` (Gap-10) — tamper-evident ring buffer.
5. `src/crc32_receipt.v` — per-decision integrity tag.
6. `src/blake3_anchor.v` — long-horizon audit anchor.
7. `src/multi_tile_receipt.v` — binds the receipt across tiles.
8. `src/d2d_holo_mesh.v` — 4-port N/E/S/W router, LAYER-FROZEN `w_tx`.
9. `src/trinity_mesh_2x2.v`, `src/trinity_router_2x2.v` — local mesh.

**Run.**

```bash
cd test
iverilog -o /tmp/tb_explain    ../src/*.v tb_explainability_unit.v
iverilog -o /tmp/tb_compose    ../src/*.v tb_composition_kernel.v
iverilog -o /tmp/tb_proof      ../src/*.v tb_proof_trace_writer.v
iverilog -o /tmp/tb_audit      ../src/*.v tb_audit_log_ring_buffer.v
for t in /tmp/tb_explain /tmp/tb_compose /tmp/tb_proof /tmp/tb_audit; do vvp $t; done

# Canonical anchor — the cross-die invariant the receipt is bound to
cd ../sim
iverilog -o /tmp/tb_canonical -I../src ../src/*.v tb_canonical.v
vvp /tmp/tb_canonical
```

**Pre-silicon target.**

| Metric | Pre-silicon target | Evidence |
|--------|---------------------|----------|
| Per-decision CRC32 receipt emitted | yes | `src/crc32_receipt.v` |
| BLAKE3 anchor advances per decision | yes | `src/blake3_anchor.v` |
| Cross-tile receipt round-trip in sim | yes | `src/multi_tile_receipt.v`, `src/d2d_holo_mesh.v` |
| Canonical anchor stable on `{uio_out,uo_out}` | `16'h47C0` | `sim/tb_canonical.v` |
| Interconnect protocol freeze | v1.0 frozen at TTSKY26b | `docs/INTERCONNECT_PROTOCOL_V1.md` |

**Falsification rule.** If the same input produces two different
receipts on two runs, or if a receipt cannot be reconstructed from the
audit-log ring buffer, this demo *fails*. That is the contract.

---

## Roll-up — what the three demos together demonstrate

| TRI-NET claim | Demo 1 | Demo 2 | Demo 3 |
|---------------|:-----:|:-----:|:-----:|
| Native ternary compute substrate | ✅ | (input side) | — |
| CLARA-aligned epistemic / safety surface | — | ✅ | (Gap-5/7) |
| Per-decision proof + audit trace | — | — | ✅ |
| Mesh / D2D transport | — | — | ✅ |
| Open PDK + open RTL, reproducible | ✅ | ✅ | ✅ |
| Measured silicon TOPS/W | ❌ | ❌ | ❌ |

When silicon returns, fill in a `docs/silicon/` directory with one
sub-file per demo containing the measured counterpart of every
estimate in the tables above. Do **not** pre-fill it.

## Sources

- BitNet b1.58 — <https://arxiv.org/abs/2402.17764>
- DARPA CLARA — <https://www.darpa.mil/research/programs/clara>
- Tiny Tapeout chips — <https://tinytapeout.com/chips/>
- [`STATUS.md`](STATUS.md), [`CLARA_TRACEABILITY.md`](CLARA_TRACEABILITY.md), [`COMPETITORS.md`](COMPETITORS.md)
