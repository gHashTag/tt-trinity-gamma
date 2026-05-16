//! Wave-44 Lane JJ'' — fbb-active-witness integration tests
//! 8 test functions for OP_FBB = 0xEE
//! anchor phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877

use fbb_active_witness::{
    gamma4_within_half_percent, power_overhead_ok, speedup_in_band, tops_w_lift_ok,
    v_fbb_in_safe_band, FbbCtrl, GAMMA4_BPS, MAC_SPEEDUP_MAX_PCT, MAC_SPEEDUP_MIN_PCT, OP_FBB,
    POWER_OVERHEAD_MAX_PCT, TOPS_W_LIFT_MIN_PCT, V_DD_MV, V_FBB_MAX_MV, V_FBB_MV,
};

/// Test 1: OP_FBB constant equals 0xEE (post ICA-W44-001).
#[test]
fn test_opcode_ee_constant() {
    assert_eq!(OP_FBB, 0xEEu8, "OP_FBB must be 0xEE after ICA-W44-001");
}

/// Test 2: Wrong opcode keeps controller off (no bias, no speed-up).
#[test]
fn test_opcode_mismatch_keeps_ctrl_off() {
    let mut c = FbbCtrl::new();
    c.step(0x00);
    assert!(!c.enabled);
    assert_eq!(c.v_fbb_mv, V_DD_MV);
    assert_eq!(c.speedup_pct, 0);
    assert_eq!(c.power_overhead_pct, 0);

    c.step(0xED); // SparsityMask must not enable FBB
    assert!(!c.enabled, "OP_SPARSE_MASK must not activate FBB");
}

/// Test 3: Correct opcode raises rail to V_FBB and lights speed-up.
#[test]
fn test_op_fbb_activates_bias_rail() {
    let mut c = FbbCtrl::new();
    c.step(OP_FBB);
    assert!(c.enabled);
    assert_eq!(c.v_fbb_mv, V_FBB_MV);
    assert!(v_fbb_in_safe_band(), "V_FBB={V_FBB_MV} not in (V_DD, V_FBB_MAX]");
    assert!(
        speedup_in_band(c.speedup_pct),
        "speedup {} out of band [{}..={}]",
        c.speedup_pct,
        MAC_SPEEDUP_MIN_PCT,
        MAC_SPEEDUP_MAX_PCT
    );
}

/// Test 4: V_FBB sits strictly between V_DD and V_FBB_MAX, ≤ 5% over V_DD.
#[test]
fn test_v_fbb_safety_band() {
    assert!(V_FBB_MV > V_DD_MV, "V_FBB must exceed V_DD");
    assert!(V_FBB_MV <= V_FBB_MAX_MV, "V_FBB must not exceed V_FBB_MAX");
    let overshoot_pct = (V_FBB_MV - V_DD_MV) * 100 / V_DD_MV;
    assert!(overshoot_pct <= 5, "overshoot {overshoot_pct}% exceeds 5% safety");
}

/// Test 5: γ⁴ Q-encoding (GAMMA4_BPS=31) within ±0.5% of φ⁻¹².
#[test]
fn test_gamma4_match_half_percent() {
    assert!(
        gamma4_within_half_percent(),
        "GAMMA4_BPS={GAMMA4_BPS} drifts > 1 bps from γ⁴"
    );
}

/// Test 6: Power overhead must stay under the 2% ceiling.
#[test]
fn test_power_overhead_bounded() {
    let c = {
        let mut tmp = FbbCtrl::new();
        tmp.step(OP_FBB);
        tmp
    };
    assert!(
        power_overhead_ok(c.power_overhead_pct),
        "overhead {} exceeds {}%",
        c.power_overhead_pct,
        POWER_OVERHEAD_MAX_PCT
    );
    // Sanity gate: 3% must fail.
    assert!(!power_overhead_ok(3));
}

/// Test 7: Wave-44 must deliver at least +7% TOPS/W lift.
#[test]
fn test_tops_w_lift_min() {
    assert!(tops_w_lift_ok(7), "+7% must pass the floor");
    assert!(tops_w_lift_ok(8), "+8% (W44 projection) must pass");
    assert!(!tops_w_lift_ok(6), "+6% must fail the floor");
    assert!(TOPS_W_LIFT_MIN_PCT == 7);
}

/// Test 8: OP_FBB is distinct from all prior ISA chain opcodes 0xE1..0xED.
#[test]
fn test_distinct_from_all_prior_opcodes() {
    let c = FbbCtrl::new();
    assert!(c.distinct_from_sparse_mask(), "must differ from OP_SPARSE_MASK (0xED)");
    assert!(c.distinct_from_drowsy_ret(),  "must differ from OP_DROWSY_RET  (0xEC)");
    assert!(c.distinct_from_spec_exit(),   "must differ from OP_SPEC_EXIT   (0xEB)");
    assert!(c.distinct_from_null_pe(),     "must differ from OP_NULL_PE     (0xEA)");
    assert!(c.distinct_from_stoch(),       "must differ from OP_STOCH_ROUND (0xE9)");
    assert!(c.distinct_from_sparse(),      "must differ from OP_SPARSE_SKIP (0xE8)");
    assert!(c.distinct_from_dfs(),         "must differ from OP_DFS_GATE    (0xE7)");
    assert!(c.distinct_from_holo_mux(),    "must differ from OP_HOLO_MUX_X4 (0xE6)");
    assert!(c.distinct_from_subth(),       "must differ from OP_SUBTH_CLK   (0xE5)");
    assert!(c.distinct_from_avs(),         "must differ from OP_AVS_RECONF  (0xE4)");
    assert!(c.distinct_from_lut_npu(),     "must differ from OP_LUT_NPU     (0xE3)");
    assert!(c.distinct_from_tom(),         "must differ from OP_TOM         (0xE2)");
    assert!(c.distinct_from_tenet(),       "must differ from OP_TENET       (0xE1)");
}
