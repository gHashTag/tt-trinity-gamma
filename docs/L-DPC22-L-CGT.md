# L-DPC22 Lane L — S-14 OpenROAD Auto Clock-Gating

**Epic:** gHashTag/trinity-fpga#93 · **Lane:** L · **Step:** S-14

## Purpose

Enable automatic clock-gating in the tt-trinity-max-true OpenLane2 flow to reduce
dynamic power consumption by approximately 12%.

## Changes

Added to `src/config.json`:

| Key | Value | Notes |
|-----|-------|-------|
| `RUN_CTS_CLOCK_GATING` | `1` | OpenLane1-compat enable flag |
| `CLOCK_GATING_MIN_RATIO` | `0.8` | Min ratio of regs controlled per gate |
| `SYNTH_CLOCK_GATING` | `true` | OpenLane2 canonical Lighter-plugin enable |

## Target

- **Gate:** ≥ 80 register groups auto-gated by Yosys/OpenROAD CGT pass.
- **Power gain:** ~ −12% dynamic power (estimated from Antmicro 2025 benchmarks).
- **Method:** Lighter Yosys plugin (`SYNTH_CLOCK_GATING`) inserts ICG cells before
  registers whose enable signals satisfy the `CLOCK_GATING_MIN_RATIO` threshold.

## Background

Automatic clock gating (ACG) replaces explicit always-enabled register clocks with
gated clocks that switch only when the register value changes. This eliminates
unnecessary toggle activity on the clock tree, reducing dynamic power proportional
to the fraction of idle cycles.

[Antmicro (2025) published measurements showing that OpenROAD's integrated CGT pass
achieves 10–15% dynamic power reduction on mid-sized designs with minimal timing
impact.](https://antmicro.com/blog/2025/07/automatic-clock-gating-in-openroad/)

The Lighter plugin (AUCOHL) integrated in OpenLane2's `Yosys.Synthesis` step performs
`reg_clock_gating` on sky130 DFF maps prior to technology mapping, enabling the
OpenROAD CTS step to treat the resulting ICG cells as first-class clock-tree sinks.

## Constraints

- `CLOCK_GATING_MIN_RATIO: 0.8` means Lighter will only insert an ICG cell for a
  group of registers when the gating enable is inactive at least 80% of clock cycles
  (static analysis estimate). This avoids power overhead from gates that switch too
  frequently.

## R-SI-1 Compliance

Zero changes to `src/*.v` synthesizable RTL. This is a pure config/docs change.
Verified by: `git diff main..feat/v15/l-cgt --stat -- src/*.v` (empty).

## Algebra Anchor

φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877

## References

- Antmicro 2025 OpenROAD CGT blog:
  https://antmicro.com/blog/2025/07/automatic-clock-gating-in-openroad/
- OpenLane2 SYNTH_CLOCK_GATING variable:
  https://github.com/efabless/openlane2/blob/main/openlane/steps/yosys.py
- Lighter clock-gating Yosys plugin:
  https://github.com/AUCOHL/Lighter
- gHashTag/trinity-fpga#93 L-DPC22 parent epic
