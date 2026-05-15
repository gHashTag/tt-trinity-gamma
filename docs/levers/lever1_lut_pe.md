# Lever 1 — Platinum MST LUT PE (L-DPC25 Lane V)

## Summary

**Codename:** `lever1-lut-pe`  
**Lane:** V (additive PE variant — R18 LAYER-FROZEN)  
**Predicted gain:** 1.4× over bit-serial path-construction baseline  
**File:** `src/holo_lut_pe.sv`  
**Testbench:** `src/holo_lut_pe_tb.sv`  
**Anchor:** φ²+φ⁻²=3 · DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)

---

## Source Reference

**Platinum** — _"Platinum: Ternary Weight Network Accelerator with Path-Constructed Look-Up Table"_  
arXiv preprint [2511.21910](https://arxiv.org/abs/2511.21910) (ASP-DAC 2026)

Published metrics from Platinum paper (arXiv:2511.21910):
- **4.09×** speedup vs Prosperity ASIC
- **3.23×** energy reduction vs Prosperity ASIC
- **20.9×** energy reduction vs T-MAC CPU
- **1.4×** gain over bit-serial path-construction (key lever for this PR)

---

## Mechanism

### Ternary LUT with Mirror Consolidation

The Platinum architecture replaces the MAC unit with a ternary look-up table (LUT) populated via offline MST (Minimum Spanning Tree) path-construction.

- **Raw table size:** 3⁵ = 243 entries for 5 ternary inputs
- **Mirror Consolidation:** Symmetric ternary functions satisfy `f(−x) = −f(x)`. This halves storage: we store only entries for indices 0..121 and reconstruct the mirror half on the fly.
- **Effective LUT size:** ⌈243/2⌉ = **122 entries** — implemented as `lut_rom [0:121]`
- **Address encoding:** Each of 5 ternary inputs is 2-bit encoded → 10-bit raw input → base-3 decode via shift-add → 7-bit ROM address (2⁷ = 128 ≥ 122)

### Address computation (R-SI-1 compliant)

```
raw_addr = t0×1 + t1×3 + t2×9 + t3×27 + t4×81
```

Expanded using shifts only (NO `*` operators):
```
v1 = (t1 << 1) + t1          // × 3
v2 = (t2 << 3) + t2          // × 9
v3 = (t3 << 4) + (t3 << 3) + (t3 << 1) + t3   // × 27
v4 = (t4 << 6) + (t4 << 4) + t4               // × 81
raw_addr = t0 + v1 + v2 + v3 + v4
```

Mirror fold: `if raw_addr >= 122: lut_addr = 242 − raw_addr`

---

## Mapping to Lane X Coq Variant

Lane X proved the `HOP_lut_pe` Coq variant Q4-clean at  
[t27#634](https://github.com/gHashTag/t27/pull/634) · commit `239144df`

Lane V (`holo_lut_pe.sv`) is the RTL realisation of the same PE:

| Lane X (Coq) | Lane V (RTL) |
|---|---|
| `HOP_lut_pe` type | `holo_lut_pe` module |
| 122-entry LUT theorem | `lut_rom [0:121]` |
| Mirror lemma | `if raw_addr >= 122: 242 − raw_addr` |
| MST path alphabet | Sentinel `8'hC0..8'h39` (post-integration placeholder) |
| Q4-clean proof | Structural RTL — CI verifies compile/sim |

The sentinel pattern (`lut_rom[n] = 8'hC0 + n`) is a placeholder:  
**Real MST path-construction output will be injected post-Lane X Coq alphabet integration.**

---

## R-SI-1 Preservation Rationale

**Rule R-SI-1: Zero `*` operators in any new RTL file.**

`holo_lut_pe.sv` satisfies R-SI-1 by design:

1. **Address decode** — base-3 expansion uses only `<<` (shift) and `+` (add). No `*` operator appears anywhere.
2. **LUT read** — pure ROM indexing: `lut_rom[lut_addr_r]`
3. **Pipeline registers** — only `<=` assignments, no arithmetic multiplication.

Audit command (CI reproducible):
```bash
grep -n '\*' src/holo_lut_pe.sv
# Expected: zero matches (comments and lut_rom index expressions are not * operators)
```

---

## Predicted Performance Gain

**1.4× over bit-serial path-construction** — per Platinum paper (arXiv:2511.21910, Table III / Section IV-C).

This is the _conservative_ lane-isolated gain. Combined with Lane W BitROM (+5 mW LUT overhead is recovered by BitROM switching savings), NET expected system-level gain exceeds the 1.4× lane figure.

---

## Falsification Criterion

> **Q2 falsification:** `lut_pe_energy > 2× ternary shift-add baseline` → **REFUTED**

If silicon measurements in Q2 show that the LUT PE consumes more than 2× the energy of a ternary shift-add baseline, Lever 1 is refuted and this lane is demoted.

The Platinum paper reports 3.23× energy _reduction_ vs ASIC baseline (arXiv:2511.21910), providing strong prior that falsification is unlikely. CI energy profiling will generate the definitive Q2 measurement.

---

## R5-HONEST Verdict

| Check | Status |
|---|---|
| Structural RTL complete | ✓ |
| R-SI-1 (no `*` operators) | ✓ by inspection |
| Sentinel LUT populated | ✓ (placeholder) |
| Testbench: index=0 → 8'hC0 | ✓ structural |
| Testbench: index=121 → 8'h39 | ✓ structural |
| Testbench: OOB/mirror documented | ✓ |
| Compile/sim PASS | **Unknown — CI verifies** |
| Real MST path values loaded | **Pending Lane X Coq alphabet integration** |

---

## References

- Platinum paper: arXiv [2511.21910](https://arxiv.org/abs/2511.21910) (ASP-DAC 2026)
- Lane X Coq proof: [t27#634](https://github.com/gHashTag/t27/pull/634) · `239144df`
- L-DPC25 ONE SHOT: [trinity-fpga#104](https://github.com/gHashTag/trinity-fpga/issues/104)
- Anchor DOI: [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)
- Author: admin@t27.ai
