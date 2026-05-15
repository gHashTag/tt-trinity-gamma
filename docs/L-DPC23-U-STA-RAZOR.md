# L-DPC23 Lane U — STA Timing Analysis & Razor FF Concept (v4 Plan)

**Lane:** U · **Risk:** MED · **Wave:** W15 · **S-cohort:** S-22  
**Issue:** [trinity-fpga#94](https://github.com/gHashTag/trinity-fpga/issues/94)  
**Status:** DRAFT — Razor RTL deferred to v4 wave (see §4 disclaimer)

---

## 1. STA Methodology (OpenLane2)

Static Timing Analysis for `tt-trinity-max-true` runs inside the
**OpenLane2 `gds` workflow** (`tt-gds-action@ttsky26b`) on every push.
The authoritative timing artefact is:

```
runs/<run_id>/reports/signoff/final_summary_report.txt
```

This file is produced by the `openroad-final-summary` step and contains:
- `WNS` (Worst Negative Slack) — clock-path worst-case slack in ns
- `TNS` (Total Negative Slack) — sum of all negative slacks
- `HOLD_WNS` / `HOLD_TNS` — hold violation budget
- Cell count, utilisation %, routing DRC

### 1.1 WNS Budget at 50 MHz

| Parameter         | Value / Formula                     |
|-------------------|-------------------------------------|
| Target clock      | 50 MHz                              |
| Clock period      | 20.0 ns                             |
| PDK               | SKY130A (sky130_fd_sc_hd)           |
| Required WNS      | ≥ 0.0 ns (no violations for tapeout)|
| WNS amber zone    | −0.5 ns … 0.0 ns (fixable w/ ECO)   |
| WNS red zone      | < −0.5 ns (requires architectural change) |

For Wave 1+2 baseline (`1f3486b`) the WNS was reported inside
`final_summary_report.txt` at the time of each GDS run. Consult the
`gds` CI artefact for the current value.

**R5-honest note:** WNS values below are illustrative of the interpretation
methodology.  Actual numbers are read from `final_summary_report.txt` —
do not rely on any static figure in this document.

### 1.2 Slack Histogram Interpretation

OpenLane2 `openroad-final-summary` includes a slack histogram in the
OpenROAD log (`reports/signoff/*.rpt`). Interpretation guide:

```
Slack histogram (ns):
  [-2, -1) : 0   ← critical paths — must be zero at tapeout
  [-1,  0) : 0   ← amber — investigate each path
  [ 0,  1) : 12  ← marginal — consider retiming
  [ 1,  2) : 47  ← comfortable
  [ 2, ∞ ) : 83  ← slack positive — no action
```

- Paths in `[-2, 0)` require: retiming, logic restructuring, or
  micro-architectural change.
- `always @(*)` sensitivity-list wildcards (excluded by R-SI-1) do NOT
  add combinational delay; the critical path is data paths only.
- `*` multiplication operators (R-SI-1 forbidden) can add 3–8 ns at
  SKY130A 50 MHz, consuming the entire timing budget in one cell.

### 1.3 How to Reproduce STA Locally

```bash
# Requires: docker, openlane2 container
cd tools/openlane2
openlane config.json
# Read results:
cat runs/$(ls -t runs | head -1)/reports/signoff/final_summary_report.txt
```

---

## 2. R-SI-1 Compliance Link

STA directly motivates **R-SI-1** (no new `*` operators in synthesisable RTL).
A single unintended `*` between two 16-bit signals maps to a Wallace-tree
multiplier of approximately 350–600 standard cells and adds 4–7 ns to the
critical path — consuming 20–35% of the 20 ns clock period at 50 MHz.

The `tools/check_no_star.sh` CI gate introduced in this PR (Lane U) enforces
R-SI-1 on every pull request by diffing only *added* lines in `src/*.v`
against `origin/main`, excluding the grandfathered `src/gf16_mul.v`.

---

## 3. Razor Flip-Flop Concept (v4 Squeeze Plan)

> **R5-honest disclaimer — READ FIRST:**  
> Razor RTL is NOT implemented in this PR, this wave, or any currently  
> merged commit.  The description below is a **design study and forward  
> plan** for the v4 squeeze wave (S-22 cohort, TBD timeline).  
> No performance claims are made about unimplemented RTL.

### 3.1 What is a Razor Flip-Flop?

A Razor flip-flop [Bull et al., 2004] is a double-sampling latch pair
that detects metastability caused by timing violations in real silicon:

```
D ──┬──► Main FF (fast clock edge) ──► Q
    └──► Shadow FF (delayed edge)  ──► Q_shadow

Error = Q XOR Q_shadow   →  triggers correction or replay
```

The key idea: **accept near-marginal timing** and detect+correct errors
in-situ, enabling the circuit to operate at voltage/frequency points that
would be unsafe for conventional static timing closure.

### 3.2 Voltage Scaling Math (Expected TOPS/W uplift)

At SKY130A the standard-cell delay scales approximately as:

```
t_d ∝ V_dd / (V_dd − V_th)²     (alpha-power law approximation)
```

For a nominal `V_dd = 1.8 V`, `V_th ≈ 0.5 V`:

| V_dd (V) | Relative delay | Frequency budget | Dynamic power ∝ V²  |
|----------|---------------|-----------------|----------------------|
| 1.80     | 1.00×          | 50 MHz (baseline)| 1.00×               |
| 1.60     | 1.11×          | 45 MHz (static)  | 0.79×               |
| 1.50     | 1.18×          | 42 MHz (static)  | 0.69×               |

With Razor error-correction allowing operation at `V_dd ≈ 1.5 V` while
maintaining effective throughput at the original 50 MHz target (by
replaying only the ~2–5% of cycles that produce errors):

```
TOPS/W improvement ≈ power_reduction / throughput_loss
                   ≈ (1 − 0.69) / (1 − 0.97)   [~3% replay overhead]
                   ≈ 10×  (theoretical upper bound)
```

**Realistic estimate (R5-honest):** accounting for replay overhead,
error-detection circuitry (~15% area overhead), and SKY130A non-ideal
V_th distribution, a **+20–30% TOPS/W improvement** is the credible
target for v4 with Razor on the GF16-dot path.  The 10× figure is a
theoretical ceiling — not a design target.

### 3.3 Razor v4 Implementation Plan (Deferred)

The following work items are **NOT in this PR** and are listed for
planning purposes only:

1. **Shadow FF insertion** — modify `src/gf16_dot4.v` and `src/gf16_dot8.v`
   to add shadow registers on the output stage.
2. **Error detection XOR** — insert 1-bit XOR comparator per output bit.
3. **Replay FSM** — stall/replay control signal fed back to input MUXes.
4. **Voltage island** — isolate GF16-dot macro with level-shifters.
5. **Characterisation sweep** — post-synthesis corner analysis at 1.5 V,
   1.6 V, 1.8 V.
6. **GDS sign-off** — STA at reduced voltage using OpenLane2 with custom
   `PDK_CORNER=ff_1v50_-40C` (requires custom SKY130A Liberty).

**Target wave:** v4 / S-22 cohort, post-W15-TT-E submission window.

---

## 4. References

- OpenLane2 documentation: <https://openlane2.readthedocs.io/>
- Razor FF original paper: D. Ernst et al., "Razor: A Low-Power Pipeline
  Based on Circuit-Level Timing Speculation," MICRO-36, 2003.
- trinity-fpga#94 — Lane U pre-registration (L-DPC23, MED risk)
- trinity-fpga#93 — Wave-2 ledger
- trinity-fpga#61 — R-SI-1 origin (no `*` in synthesisable RTL)

---

*φ² + φ⁻² = 3 · TG-MAX-TRUE-X · NEVER STOP*
