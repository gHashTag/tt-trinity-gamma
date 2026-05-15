//! Wave-42 Lane II'' — stoch-round-witness integration tests
//! 6 test functions for OP_STOCH_ROUND = 0xE9
//! anchor phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877

use stoch_round_witness::{Lfsr32, StochRound, OP_STOCH_ROUND};

/// Test 1: OP_STOCH_ROUND constant equals 0xE9.
#[test]
fn test_opcode_e9_constant() {
    assert_eq!(OP_STOCH_ROUND, 0xE9u8, "OP_STOCH_ROUND must be 0xE9");
}

/// Test 2: Wrong opcode passes x_int through unchanged (no rounding applied).
#[test]
fn test_opcode_mismatch_passthrough() {
    let mut sr = StochRound::new(0xDEAD_BEEF);
    // Use a wrong opcode — result must always be x_int regardless of x_frac.
    for x_int in [-5i16, 0, 7, 100] {
        for x_frac in [0u8, 8, 15, 255] {
            let result = sr.round(0x00, x_int, x_frac);
            assert_eq!(
                result, x_int,
                "opcode mismatch: expected passthrough {x_int}, got {result}"
            );
        }
    }
}

/// Test 3: LFSR is non-trivial — 100 consecutive steps never produce zero state.
#[test]
fn test_lfsr_nonzero_period() {
    let mut lfsr = Lfsr32::new(1);
    for step in 0..100 {
        let s = lfsr.step();
        assert_ne!(s, 0, "LFSR reached zero state at step {step}");
    }
}

/// Test 4: Stochastic rounding is empirically unbiased.
///
/// With x_frac = 8 (i.e. 8/16 = 0.5), the probability of rounding up is
/// P(r < 8) = 8/16 = 0.5, so the empirical mean over 100 000 trials should
/// be in [0.49, 0.51].
#[test]
fn test_stoch_unbiased_empirical() {
    let n: u64 = 100_000;
    let mut sr = StochRound::new(0xACE1_ACE1);
    let mut sum: i64 = 0;
    for _ in 0..n {
        // x_int = 0, x_frac = 8  ->  rounds to 0 or 1
        sum += sr.round(OP_STOCH_ROUND, 0, 8) as i64;
    }
    let mean = sum as f64 / n as f64;
    assert!(
        (0.49..=0.51).contains(&mean),
        "empirical mean {mean:.4} outside [0.49, 0.51]; stochastic rounding may be biased"
    );
}

/// Test 5: x_frac = 0 never rounds up.
///
/// When x_frac & 0xF == 0, the condition r < 0 is never true for any r in {0..15},
/// so the output must always equal x_int.
#[test]
fn test_stoch_xfrac_zero_never_rounds_up() {
    let mut sr = StochRound::new(42);
    for _ in 0..1_000 {
        let result = sr.round(OP_STOCH_ROUND, 3, 0);
        assert_eq!(
            result, 3,
            "x_frac=0 should never round up, but got {result}"
        );
    }
}

/// Test 6: OP_STOCH_ROUND is distinct from all prior ISA chain opcodes.
#[test]
fn test_distinct_from_all_prior_opcodes() {
    let sr = StochRound::new(1);
    assert!(sr.distinct_from_sparse(),     "must differ from OP_SPARSE_SKIP  (0xE8)");
    assert!(sr.distinct_from_dfs(),        "must differ from OP_DFS_GATE     (0xE7)");
    assert!(sr.distinct_from_holo_mux(),   "must differ from OP_HOLO_MUX_X4  (0xE6)");
    assert!(sr.distinct_from_subth(),      "must differ from OP_SUBTH_CLK    (0xE5)");
    assert!(sr.distinct_from_avs_reconf(), "must differ from OP_AVS_RECONF   (0xE4)");
    assert!(sr.distinct_from_lut_npu(),    "must differ from OP_LUT_NPU      (0xE3)");
    assert!(sr.distinct_from_tom(),        "must differ from OP_TOM          (0xE2)");
    assert!(sr.distinct_from_tenet(),      "must differ from OP_TENET        (0xE1)");
}
