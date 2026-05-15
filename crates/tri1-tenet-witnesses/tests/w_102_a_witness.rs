// SPDX-License-Identifier: Apache-2.0
// Authors: Vasilev Dmitrii <admin@t27.ai>
//
// W-102-A Integration Test — TENET Sparsity Ratio Bound
// L-DPC26 Wave-29 · Lane T''' (Triple-Prime)
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ R7 FALSIFICATION WITNESS                                                │
// │                                                                         │
// │ PRE-SILICON (now): test uses a SYNTHETIC measurement derived from the   │
// │ BitNet b1.58 2B4T paper (arXiv:2504.12285) which reports ~30 % zero    │
// │ weights. Synthetic values: skip_count = 300_000, total = 1_000_000,    │
// │ ratio = 0.30 → PASSES (0.30 ≥ 0.25).                                  │
// │                                                                         │
// │ POST-SILICON (after verdict 2026-10-15): this test is re-run with real │
// │ counters from verdict.json produced by the sparsity_skip RTL           │
// │ controller (Lane T). If measured_sparsity < 0.25, this test FAILS      │
// │ → FAIL-STOP per Wave-29 R7 policy.                                     │
// │                                                                         │
// │ Mirrors Coq proof: gHashTag/t27 PR #644 (SHA 367a7ba64e),              │
// │ Lemma tenet_no_star, opcode OP_SPARSE_SKIP = 0xE1.                     │
// └─────────────────────────────────────────────────────────────────────────┘

use tri1_tenet_witnesses::{meets_sparsity_bound, SparsityMeasurement, SPARSITY_LOWER_BOUND};

/// W-102-A: BitNet b1.58-3B sparsity ratio must be ≥ SPARSITY_LOWER_BOUND (0.25).
///
/// Pre-silicon synthetic measurement sourced from BitNet b1.58 2B4T paper
/// (arXiv:2504.12285): ~30 % zero weights → skip_count=300_000 / total=1_000_000.
///
/// Post-silicon: replace synthetic counters with real RTL verdict.json values.
/// If real_sparsity < 0.25 this test FAILS → fail-stop (R7 policy, Wave-29).
#[test]
fn w_102_a_sparsity_ratio_bound() {
    // PRE-SILICON ESTIMATE: synthetic measurement from BitNet b1.58 2B4T
    // (arXiv:2504.12285, ~30% zero weights). R5-HONEST label applies.
    let measurement = SparsityMeasurement::new(
        300_000,   // skip_count  — PRE-SILICON ESTIMATE
        1_000_000, // total_lookups — PRE-SILICON ESTIMATE
    );

    let measured = measurement.ratio(); // 0.30 pre-silicon

    assert!(
        meets_sparsity_bound(measured),
        "W-102-A FAIL: measured sparsity {:.4} < lower bound {:.4}. \
         R7 fail-stop triggered. Real RTL counters do not meet the \
         ≥25% sparsity requirement for BitNet b1.58-3B / OP_SPARSE_SKIP=0xE1. \
         See trios#845 and Coq lemma tenet_no_star (t27#644 @ 367a7ba64e).",
        measured,
        SPARSITY_LOWER_BOUND,
    );
}
