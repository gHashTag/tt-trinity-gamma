//! Wave-45 Lane KK'' — wl-boost-witness integration tests
//! 12 test functions for OP_WL_BOOST = 0xEF
//! anchor phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877

use wl_boost_witness::{
    coupling_identity_holds, gamma2_within_2_bps, net_saving_ok, op_wl_boost_constant_ef,
    read_margin_in_band, tops_w_lift_ok, vdd_new_ratio_in_band, wl_driver_overhead_ok,
    wl_power_saving_at_least_10pct, wl_voltage_ratio_in_band, GAMMA2_BPS, NET_SAVING_MIN_PCT,
    OP_WL_BOOST, POWER_SAVING_MIN_PCT, READ_MARGIN_MAX_MV, READ_MARGIN_MIN_MV, READ_MARGIN_MV,
    TOPS_W_LIFT_MIN_PCT, V_DD_MV, V_DD_NEW_MV, V_WL_MV, WL_DRV_OVERHEAD_MAX_PCT, WlBoostCtrl,
};

/// Test 1: OP_WL_BOOST constant equals 0xEF (sacred slot 15).
#[test]
fn test_op_wl_boost_constant_ef() {
    assert_eq!(OP_WL_BOOST, 0xEFu8, "OP_WL_BOOST must be 0xEF (sacred slot 15)");
    assert!(op_wl_boost_constant_ef(), "constant function must agree");
}

/// Test 2: Wrong opcode keeps controller off.
#[test]
fn test_opcode_mismatch_keeps_ctrl_off() {
    let mut c = WlBoostCtrl::new();
    c.step(0x00);
    assert!(!c.enabled);
    assert_eq!(c.v_wl_mv, V_DD_MV);
    assert_eq!(c.v_dd_new_mv, V_DD_MV);
    assert_eq!(c.gross_save_pct, 0);

    c.step(0xEE); // FBB must not enable WL boost
    assert!(!c.enabled, "OP_FBB must not activate WL_BOOST");
    c.step(0xED); // SparseMask must not enable WL boost
    assert!(!c.enabled, "OP_SPARSE_MASK must not activate WL_BOOST");
}

/// Test 3: Correct opcode raises V_WL and reduces V_DD coupled.
#[test]
fn test_op_wl_boost_activates_dual_rail() {
    let mut c = WlBoostCtrl::new();
    c.step(OP_WL_BOOST);
    assert!(c.enabled);
    assert_eq!(c.v_wl_mv, V_WL_MV);
    assert_eq!(c.v_dd_new_mv, V_DD_NEW_MV);
    assert!(c.v_wl_mv > V_DD_MV, "V_WL must exceed V_DD");
    assert!(c.v_dd_new_mv < V_DD_MV, "V_DD_new must drop below V_DD");
}

/// Test 4: V_WL/V_DD ratio in canonical band [1.0552, 1.0562].
#[test]
fn test_wl_voltage_ratio_in_band() {
    assert!(
        wl_voltage_ratio_in_band(),
        "V_WL/V_DD={}/{} = {}/10000, expected [10552, 10562]",
        V_WL_MV,
        V_DD_MV,
        V_WL_MV * 10000 / V_DD_MV
    );
}

/// Test 5: V_DD_new/V_DD ratio in canonical band [0.9438, 0.9448].
#[test]
fn test_vdd_new_ratio_in_band() {
    assert!(
        vdd_new_ratio_in_band(),
        "V_DD_new/V_DD={}/{} = {}/10000, expected [9437, 9448]",
        V_DD_NEW_MV,
        V_DD_MV,
        V_DD_NEW_MV * 10000 / V_DD_MV
    );
}

/// Test 6: Charge-pump coupling identity V_WL + V_DD_new ≈ 2·V_DD.
#[test]
fn test_coupling_identity_holds() {
    assert!(
        coupling_identity_holds(),
        "V_WL + V_DD_new = {} + {} = {}, target 2·V_DD = {}",
        V_WL_MV,
        V_DD_NEW_MV,
        V_WL_MV + V_DD_NEW_MV,
        2 * V_DD_MV
    );
}

/// Test 7: γ² Q-encoding within 2 bps of φ⁻⁶.
#[test]
fn test_gamma2_match_2bps() {
    assert!(
        gamma2_within_2_bps(),
        "GAMMA2_BPS={GAMMA2_BPS} drifts > 2 bps from γ²=φ⁻⁶ ≈ 557 bps"
    );
}

/// Test 8: Read margin invariant 88 mV in band [60, 120].
#[test]
fn test_read_margin_invariant_88mV() {
    assert_eq!(READ_MARGIN_MV, 88, "canonical read margin must equal 88 mV");
    assert!(read_margin_in_band(READ_MARGIN_MV), "88 mV must be in band");
    assert!(read_margin_in_band(READ_MARGIN_MIN_MV), "60 mV (band low) must pass");
    assert!(read_margin_in_band(READ_MARGIN_MAX_MV), "120 mV (band high) must pass");
    assert!(!read_margin_in_band(59), "59 mV (under low) must fail");
    assert!(!read_margin_in_band(121), "121 mV (over high) must fail");
}

/// Test 9: WL boost active controller preserves read margin at 88 mV.
#[test]
fn test_ctrl_preserves_read_margin() {
    let mut c = WlBoostCtrl::new();
    c.step(OP_WL_BOOST);
    assert_eq!(c.read_margin_mv, READ_MARGIN_MV);
    assert!(read_margin_in_band(c.read_margin_mv));
}

/// Test 10: Gross dynamic-power saving ≥ 10 %.
#[test]
fn test_wl_power_saving_at_least_10pct() {
    let mut c = WlBoostCtrl::new();
    c.step(OP_WL_BOOST);
    assert!(
        wl_power_saving_at_least_10pct(c.gross_save_pct),
        "gross save {} must meet {} %",
        c.gross_save_pct,
        POWER_SAVING_MIN_PCT
    );
    // Boundary sanity:
    assert!(wl_power_saving_at_least_10pct(10), "10 % must pass floor");
    assert!(wl_power_saving_at_least_10pct(11), "11 % must pass floor");
    assert!(!wl_power_saving_at_least_10pct(9), "9 % must fail floor");
}

/// Test 11: WL-driver overhead ≤ 3 % AND net saving ≥ 7 %.
#[test]
fn test_wl_driver_overhead_and_net_saving() {
    let mut c = WlBoostCtrl::new();
    c.step(OP_WL_BOOST);
    assert!(
        wl_driver_overhead_ok(c.driver_overhead_pct),
        "WL driver overhead {} exceeds {} %",
        c.driver_overhead_pct,
        WL_DRV_OVERHEAD_MAX_PCT
    );
    // 4% must fail
    assert!(!wl_driver_overhead_ok(4));
    // Net saving floor
    assert!(
        net_saving_ok(c.net_save_pct()),
        "net save {} below {} %",
        c.net_save_pct(),
        NET_SAVING_MIN_PCT
    );
    // 6% must fail net floor
    assert!(!net_saving_ok(6));
}

/// Test 12: TOPS/W lift ≥ 6 % AND distinct from all 14 prior opcodes.
#[test]
fn test_tops_w_lift_and_distinctness() {
    assert!(tops_w_lift_ok(6), "+6% must pass the floor");
    assert!(tops_w_lift_ok(8), "+8% (W45 projection) must pass");
    assert!(!tops_w_lift_ok(5), "+5% must fail the floor");
    assert!(TOPS_W_LIFT_MIN_PCT == 6);

    let c = WlBoostCtrl::new();
    assert!(c.distinct_from_fbb(),         "must differ from OP_FBB         (0xEE)");
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
