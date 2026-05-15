//! Wave-41 Lane GG'' — integration tests for sparse-witness
//! 6 #[test] functions verifying OP_SPARSE_SKIP=0xE8 + SparseGate behaviour.

use sparse_witness::{OP_SPARSE_SKIP, SparseGate};

/// Test 1 — sacred opcode constant is exactly 0xE8.
#[test]
fn test_opcode_e8_constant() {
    assert_eq!(OP_SPARSE_SKIP, 0xE8, "OP_SPARSE_SKIP must be 0xE8");
}

/// Test 2 — activation below threshold and topk_keep=false → skip (true).
#[test]
fn test_skip_when_below_threshold() {
    // tau = 0x10 → decoded = (0x10 & 0x1F) << ((0x10 >> 5) & 0x7)
    //                       = 16 << 0 = 16
    let mut gate = SparseGate::new(0x10);
    // |activation| = 5 < 16 → should skip
    let result = gate.should_skip(OP_SPARSE_SKIP, 5, false);
    assert!(result, "should skip when |activation| < tau_decoded and topk_keep=false");
}

/// Test 3 — activation at or above threshold → no skip (false).
#[test]
fn test_no_skip_when_above_threshold() {
    // tau = 0x08 → decoded = 8 << 0 = 8
    let mut gate = SparseGate::new(0x08);
    // |activation| = 10 >= 8 → should NOT skip
    let result = gate.should_skip(OP_SPARSE_SKIP, 10, false);
    assert!(!result, "should not skip when |activation| >= tau_decoded");

    // Exactly at threshold: |activation| = 8 >= 8 → should NOT skip
    let result_eq = gate.should_skip(OP_SPARSE_SKIP, 8, false);
    assert!(!result_eq, "should not skip when |activation| == tau_decoded");
}

/// Test 4 — topk_keep=true forces gate open, no skip regardless of activation.
#[test]
fn test_topk_keep_overrides() {
    // tau = 0x01 → decoded = 1 (very low threshold — almost everything would skip)
    let mut gate = SparseGate::new(0x01);
    // Even though |activation|=0 < 1, topk_keep=true prevents skip
    let result = gate.should_skip(OP_SPARSE_SKIP, 0, true);
    assert!(!result, "topk_keep=true must prevent skip even below threshold");
    assert_eq!(gate.sparsity_cnt, 0, "sparsity_cnt must not increment when topk_keep=true");
}

/// Test 5 — OP_SPARSE_SKIP is distinct from all prior opcodes 0xE7..0xE1 and 0xD0..0xE0.
#[test]
fn test_distinct_from_all_prior_opcodes() {
    let gate = SparseGate::new(0x00);
    // Explicit chain
    assert!(gate.distinct_from_dfs(),       "must differ from 0xE7 OP_DFS_GATE");
    assert!(gate.distinct_from_holo_mux(),  "must differ from 0xE6 OP_HOLO_MUX_X4");
    assert!(gate.distinct_from_subth(),     "must differ from 0xE5 OP_SUBTH_CLK");
    assert!(gate.distinct_from_avs(),       "must differ from 0xE4 OP_AVS_RECONF");
    assert!(gate.distinct_from_lut_npu(),   "must differ from 0xE3 OP_LUT_NPU");
    assert!(gate.distinct_from_tom(),       "must differ from 0xE2 OP_TOM");
    assert!(gate.distinct_from_tenet(),     "must differ from 0xE1 OP_TENET");
    // Lower range D0..E0
    assert!(gate.distinct_from_lower_range(), "must differ from 0xD0..=0xE0 range");
    // Exhaustive check over the full prior range
    for opcode in 0xD0u8..=0xE7u8 {
        assert_ne!(
            OP_SPARSE_SKIP, opcode,
            "OP_SPARSE_SKIP=0xE8 must differ from prior opcode 0x{:02X}",
            opcode
        );
    }
}

/// Test 6 — calling should_skip 5 times where each returns true → sparsity_cnt == 5.
#[test]
fn test_sparsity_counter_increments() {
    // tau = 0x14 → decoded = (0x14 & 0x1F) << ((0x14 >> 5) & 0x7)
    //                       = 20 << 0 = 20
    let mut gate = SparseGate::new(0x14);
    for i in 0..5 {
        let skipped = gate.should_skip(OP_SPARSE_SKIP, 1, false); // |1| < 20 → true
        assert!(skipped, "iteration {}: expected skip=true", i);
    }
    assert_eq!(gate.sparsity_cnt, 5, "sparsity_cnt must equal 5 after 5 skips");
}
