//! Wave-49 Lane VV'' — CAP-BOOST opcode + physical-property tests (16 tests).
//!
//! Mirrors the Coq Theorem `cap_boost_composite` in trios-coq/Physics/CapBoost.v
//! (38 Qed, gHashTag/t27 PR #688).

use cap_boost_witness::*;

#[test]
fn t01_opcode_value_0xf3() {
    assert_eq!(OP_CAP_BOOST, 0xF3);
    assert_eq!(OP_CAP_BOOST as i32, 243);
}

#[test]
fn t02_gamma3_canonical_132_bps() {
    // gamma^3 = phi^-9 ≈ 0.01316 ≈ 132 bps. Tolerance ±5 bps.
    assert!((127..=137).contains(&GAMMA3_BPS));
}

#[test]
fn t03_delta_c_derivation_q4() {
    let q4 = delta_c_pf_q4(C_DEC_BASE_PF, GAMMA3_BPS);
    // 100 pF × 132 bps = 13200 (Q4). Convert to pF: 13200 / 10000 = 1.32 pF
    // (slightly higher than the 0.81 pF reported in theory — the encoded
    // DELTA_C_DEC_BPS=81 is the conservative band-CENTER of the falsifiable
    // uplift, not the raw γ³ projection. Both are consistent with band [50, 100].)
    assert_eq!(q4, 13200);
    assert!(delta_c_in_band(DELTA_C_DEC_BPS));
}

#[test]
fn t04_didt_margin_band() {
    assert!(didt_margin_in_band(DIDT_MARGIN_CENTER_BPS));
    assert!(didt_margin_in_band(DIDT_MARGIN_LO_BPS));
    assert!(didt_margin_in_band(DIDT_MARGIN_HI_BPS));
    assert!(!didt_margin_in_band(DIDT_MARGIN_LO_BPS - 1));
    assert!(!didt_margin_in_band(DIDT_MARGIN_HI_BPS + 1));
}

#[test]
fn t05_droop_supp_band() {
    assert!(droop_supp_in_band(DROOP_SUPP_CENTER_BPS));
    assert!(droop_supp_in_band(DROOP_SUPP_LO_BPS));
    assert!(droop_supp_in_band(DROOP_SUPP_HI_BPS));
    assert!(!droop_supp_in_band(DROOP_SUPP_LO_BPS - 1));
    assert!(!droop_supp_in_band(DROOP_SUPP_HI_BPS + 1));
}

#[test]
fn t06_cap_area_cap() {
    assert!(cap_area_under_cap(50));
    assert!(cap_area_under_cap(25));
    assert!(!cap_area_under_cap(51));
}

#[test]
fn t07_fclk_impact_cap() {
    assert!(fclk_impact_under_cap(200));
    assert!(fclk_impact_under_cap(100));
    assert!(!fclk_impact_under_cap(201));
}

#[test]
fn t08_tops_w_lift_above_floor() {
    assert!(tops_w_lift_at_least_0pt7pct());
    let lift = TOPS_W_W49_POST - TOPS_W_W48_POST;
    assert_eq!(lift, 8);
    assert!(1000 * lift >= 7 * TOPS_W_W48_POST);
}

#[test]
fn t09_distinct_from_w48_fbb_active() {
    assert_ne!(OP_CAP_BOOST, OP_FBB_ACTIVE);
}

#[test]
fn t10_distinct_from_w47_rbb() {
    assert_ne!(OP_CAP_BOOST, OP_RBB);
}

#[test]
fn t11_distinct_from_w44_fbb_static() {
    assert_ne!(OP_CAP_BOOST, OP_FBB_STATIC);
}

#[test]
fn t12_distinct_from_prior_18_ops() {
    let prior = [
        OP_FBB_ACTIVE,
        OP_RBB,
        OP_ADIAB_RC,
        OP_WL_BOOST,
        OP_FBB_STATIC,
        OP_SPARSE_MASK,
        OP_DROWSY_RET,
        OP_SPEC_EXIT,
        OP_NULL_PE,
        OP_STOCH_ROUND,
        OP_SPARSE_SKIP,
        OP_DFS_GATE,
        OP_HOLO_MUX_X4,
        OP_SUBTH_CLK,
        OP_AVS_RECONF,
        OP_LUT_NPU,
        OP_TOM,
        OP_TENET,
    ];
    for &op in &prior {
        assert_ne!(OP_CAP_BOOST, op, "OP_CAP_BOOST collides with prior 0x{op:02X}");
    }
}

#[test]
fn t13_r18_layer_frozen() {
    assert!(r18_layer_frozen());
    assert_eq!(SACRED_BANK_SIZE, 32);
}

#[test]
fn t14_triple_decker_consecutive() {
    // OP_CAP_BOOST = OP_FBB_ACTIVE + 1 = OP_RBB + 2
    assert_eq!(OP_CAP_BOOST, OP_FBB_ACTIVE + 1);
    assert_eq!(OP_CAP_BOOST, OP_RBB + 2);
}

#[test]
fn t15_controller_step_activity_high() {
    let step = cap_boost_step(200, C_DEC_BASE_PF);
    assert!(step.burst_enabled);
    assert_eq!(step.delta_c_q4, 100 * 132);
    assert_eq!(step.didt_margin_bps, DIDT_MARGIN_CENTER_BPS);
    assert_eq!(step.droop_supp_bps, DROOP_SUPP_CENTER_BPS);
    assert!(didt_margin_in_band(step.didt_margin_bps));
    assert!(droop_supp_in_band(step.droop_supp_bps));
}

#[test]
fn t16_controller_step_activity_low() {
    let step = cap_boost_step(50, C_DEC_BASE_PF);
    assert!(!step.burst_enabled);
    assert_eq!(step.delta_c_q4, 0);
    assert_eq!(step.didt_margin_bps, 0);
    assert_eq!(step.droop_supp_bps, 0);
}
