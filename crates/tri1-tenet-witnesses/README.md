# tri1-tenet-witnesses

**R7 Rust falsification witness W-102-A** for L-DPC26 Wave-29 TENET sparsity-aware LUT.
Part of the [tt-trinity-max-true](https://github.com/gHashTag/tt-trinity-max-true) workspace.

## Overview

This crate implements **W-102-A**, the runtime falsifier for **Lever #3** of the TENET sparsity-aware LUT architecture. It enforces the constitutional R7 bound:

> BitNet b1.58-3B workloads processed through the `sparsity_skip` RTL controller (opcode `OP_SPARSE_SKIP = 0xE1`) must achieve a sparsity ratio **≥ 25 %** (i.e., at least 25 % of LUT lookups are skipped).

### Connection to Lane T' Coq proof

This witness mirrors the Coq formalization:

- **Repo**: [gHashTag/t27](https://github.com/gHashTag/t27)
- **PR**: [#644](https://github.com/gHashTag/t27/pull/644) @ SHA `367a7ba64e`
- **Lemma**: `tenet_no_star`
- **Opcode**: `OP_SPARSE_SKIP = 0xE1`

The Coq lemma establishes that any execution trace satisfying the TENET constraints contains no `*` (star) free-variables in the sparsity map — a necessary condition for ≥ 25 % skip coverage. This Rust crate provides the runtime complement: if the hardware/firmware deviates from the proof's preconditions, `w_102_a_sparsity_ratio_bound` fails at test time.

## Mission reference

- **Tracking issue**: [gHashTag/trios#845](https://github.com/gHashTag/trios/issues/845)
- **Wave**: Wave-29 · L-DPC26
- **Lane**: T''' (Triple-Prime)

## API

```rust
use tri1_tenet_witnesses::{SPARSITY_LOWER_BOUND, meets_sparsity_bound, SparsityMeasurement};

// Constitutional lower bound (PRE-SILICON ESTIMATE, frozen 2026-08-15)
assert_eq!(SPARSITY_LOWER_BOUND, 0.25);

// Check a measurement
let m = SparsityMeasurement::new(300_000, 1_000_000);
assert!(meets_sparsity_bound(m.ratio())); // 0.30 ≥ 0.25 → OK
```

## Tests

```
cargo test -p tri1-tenet-witnesses
```

Expected output (pre-silicon):

```
test w_102_a_sparsity_ratio_bound ... ok

test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured
```

## R7 Falsification Policy (Wave-29)

| Phase | `skip_count / total` | Result |
|---|---|---|
| Pre-silicon (now) | 0.30 (synthetic, arXiv:2504.12285) | ✅ PASS |
| Post-silicon (after 2026-10-15) | Real RTL `verdict.json` counters | ✅ if ≥ 0.25, ❌ FAIL-STOP if < 0.25 |

A FAIL triggers the Wave-29 R7 fail-stop policy: the entire lane is quarantined pending re-measurement.

## Constitutional compliance

| Rule | Status |
|---|---|
| R5-HONEST | ✅ All constants labelled `// PRE-SILICON ESTIMATE` |
| R7 falsification | ✅ Test asserts `measured >= SPARSITY_LOWER_BOUND` |
| R8 author identity | ✅ `admin@t27.ai` |
| R18 LAYER-FROZEN | ✅ New crate only; Lane N `tri1-lever-stack-witnesses` untouched |
| Apache-2.0 | ✅ |

## Authors

Vasilev Dmitrii &lt;admin@t27.ai&gt;
