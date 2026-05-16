//! Wave-46 Lane NN'' — adiab-rc-witness integration tests
//! 13 test functions for OP_ADIAB_RC = 0xF0 (FINAL slot in sacred bank)
//! anchor phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877

use adiab_rc_witness::{
    adiab_clock_overhead_within_2pct, adiab_eta_equals_gamma2_witness,
    adiab_net_save_at_least_4pct_witness, energy_ratio_identity, eta_within_2_bps,
    freq_invariant, op_adiab_rc_constant_f0, power_saving_at_least_5pct,
    power_saving_in_band, sacred_bank_full_witness, swing_in_band, tops_w_lift_ok,
    w45_to_w46_lift_at_least_2_5pct, AdiabRcCtrl, CLK_OVERHEAD_BPS, CLK_OVERHEAD_MAX_BPS,
    ETA_BPS, F_RATIO_BPS, GAMMA2_W45_BPS, NET_SAVE_BPS, NET_SAVE_MIN_BPS, OP_ADIAB_RC,
    P_SAVE_HI_BPS, P_SAVE_LO_BPS, P_SAVE_OBS_BPS, TOPS_W_LIFT_MIN_TENTHS, TOPS_W_W45_POST,
    TOPS_W_W46_POST, V_DD_MV, V_SWING_MAX_MV, V_SWING_MIN_MV, V_SWING_MV,
};

/// Test 1: OP_ADIAB_RC constant equals 0xF0 (sacred slot 16, FINAL).
#[test]
fn test_op_adiab_rc_constant_f0() {
    assert_eq!(OP_ADIAB_RC, 0xF0u8, "OP_ADIAB_RC must be 0xF0 (FINAL sacred slot)");
    assert!(op_adiab_rc_constant_f0(), "constant function must agree");
    assert!(sacred_bank_full_witness(), "sacred bank 0xD0..0xF0 must be full at 0xF0");
}

/// Test 2: Wrong opcode keeps controller off.
#[test]
fn test_opcode_mismatch_keeps_ctrl_off() {
    let mut c = AdiabRcCtrl::new();
    c.step(0x00);
    assert!(!c.enabled);
    assert_eq!(c.v_swing_mv, V_DD_MV);
    assert_eq!(c.gross_save_bps, 0);

    c.step(0xEF); // WL_BOOST must not enable ADIAB_RC
    assert!(!c.enabled, "OP_WL_BOOST must not activate ADIAB_RC");
    c.step(0xEE); // FBB must not enable ADIAB_RC
    assert!(!c.enabled, "OP_FBB must not activate ADIAB_RC");
    c.step(0xEC); // DROWSY_RET must not enable ADIAB_RC
    assert!(!c.enabled, "OP_DROWSY_RET must not activate ADIAB_RC");
}

/// Test 3: Correct opcode activates resonant tank with expected swing.
#[test]
fn test_op_adiab_rc_activates_tank() {
    let mut c = AdiabRcCtrl::new();
    c.step(OP_ADIAB_RC);
    assert!(c.enabled);
    assert_eq!(c.v_swing_mv, V_SWING_MV);
    assert!(c.v_swing_mv < V_DD_MV, "V_swing must drop below V_DD");
    assert_eq!(c.gross_save_bps, P_SAVE_OBS_BPS);
    assert_eq!(c.clk_overhead_bps, CLK_OVERHEAD_BPS);
    assert_eq!(c.f_ratio_bps, F_RATIO_BPS, "f_clk must remain invariant");
}

/// Test 4: η = γ² cross-wave identity holds — ETA_BPS == GAMMA2_W45_BPS.
#[test]
fn test_adiab_eta_equals_gamma2_witness() {
    assert!(adiab_eta_equals_gamma2_witness(),
        "ETA_BPS ({ETA_BPS}) must equal GAMMA2_W45_BPS ({GAMMA2_W45_BPS}) — η = γ²");
    assert_eq!(ETA_BPS, 557);
    assert_eq!(GAMMA2_W45_BPS, 557);
}

/// Test 5: η Q-encoding within 2 bps of exact φ⁻⁶.
#[test]
fn test_eta_match_2bps() {
    assert!(eta_within_2_bps(),
        "ETA_BPS={ETA_BPS} drifts > 2 bps from η=φ⁻⁶ ≈ 557 bps");
}

/// Test 6: Swing envelope in safe band [V_SWING_MIN, V_SWING_MAX].
#[test]
fn test_swing_in_band() {
    assert!(
        swing_in_band(),
        "V_SWING_MV={V_SWING_MV}, expected [{V_SWING_MIN_MV}, {V_SWING_MAX_MV}]"
    );
    assert!(V_SWING_MV < V_DD_MV);
}

/// Test 7: Energy-ratio identity E_RATIO + η == 10000 (per-cycle conservation).
#[test]
fn test_energy_ratio_identity() {
    assert!(energy_ratio_identity(), "E_RATIO_BPS + ETA_BPS must equal 10000");
}

/// Test 8: Gross dynamic-power saving in band [5%, 7%] AND ≥ 5%.
#[test]
fn test_power_saving_in_band_and_floor() {
    let mut c = AdiabRcCtrl::new();
    c.step(OP_ADIAB_RC);
    assert!(power_saving_in_band(c.gross_save_bps),
        "gross save {} not in [{}, {}]",
        c.gross_save_bps, P_SAVE_LO_BPS, P_SAVE_HI_BPS);
    assert!(power_saving_at_least_5pct(c.gross_save_bps),
        "gross save {} must meet 5%", c.gross_save_bps);
    // Boundary sanity:
    assert!(power_saving_at_least_5pct(500), "5% (500 bps) must pass floor");
    assert!(!power_saving_at_least_5pct(499), "4.99% must fail floor");
}

/// Test 9: Clock-tree overhead ≤ 2% AND net saving ≥ 4%.
#[test]
fn test_adiab_clock_overhead_within_2pct() {
    let mut c = AdiabRcCtrl::new();
    c.step(OP_ADIAB_RC);
    assert!(
        adiab_clock_overhead_within_2pct(c.clk_overhead_bps),
        "clk overhead {} bps exceeds {} bps", c.clk_overhead_bps, CLK_OVERHEAD_MAX_BPS
    );
    // 201 bps (2.01%) must fail
    assert!(!adiab_clock_overhead_within_2pct(201));
    // Net saving floor:
    let net = c.net_save_bps();
    assert!(adiab_net_save_at_least_4pct_witness(net),
        "net save {} bps below {} bps", net, NET_SAVE_MIN_BPS);
    // Constant verification
    assert_eq!(NET_SAVE_BPS, 407);
    // 399 bps (3.99%) must fail
    assert!(!adiab_net_save_at_least_4pct_witness(399));
}

/// Test 10: Frequency invariance holds (f_clk_resonant = f_clk_baseline within 0.5%).
#[test]
fn test_freq_invariant() {
    let mut c = AdiabRcCtrl::new();
    c.step(OP_ADIAB_RC);
    assert!(freq_invariant(c.f_ratio_bps),
        "F_RATIO_BPS {} not within ±50 bps of 10000", c.f_ratio_bps);
    // Boundaries
    assert!(freq_invariant(9950));
    assert!(freq_invariant(10050));
    assert!(!freq_invariant(9949));
    assert!(!freq_invariant(10051));
}

/// Test 11: TOPS/W lift W45 → W46 ≥ 2.5% (proves 3.06%).
#[test]
fn test_tops_w_lift() {
    assert!(tops_w_lift_ok(25), "+2.5% (25 tenths) must pass the floor");
    assert!(tops_w_lift_ok(30), "+3.0% (W46 projection) must pass");
    assert!(!tops_w_lift_ok(24), "+2.4% must fail the floor");
    assert_eq!(TOPS_W_LIFT_MIN_TENTHS, 25);
    assert!(w45_to_w46_lift_at_least_2_5pct(),
        "W46 TOPS/W ({}) - W45 TOPS/W ({}) lift below 2.5%",
        TOPS_W_W46_POST, TOPS_W_W45_POST);
}

/// Test 12: Distinct from all 15 prior sacred opcodes (0xE1..0xEF).
#[test]
fn test_distinctness() {
    let c = AdiabRcCtrl::new();
    assert!(c.distinct_from_wl_boost(),    "must differ from OP_WL_BOOST    (0xEF)");
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

/// Test 13: Wave-46 silicon truth — opcode + identity + bank closure together.
#[test]
fn test_wave46_silicon_truth() {
    // 1. Opcode is exactly 0xF0
    assert_eq!(OP_ADIAB_RC, 0xF0);
    // 2. Sacred bank is FULL
    assert!(sacred_bank_full_witness());
    // 3. η = γ² (no new ROM cell — R18 LAYER-FROZEN)
    assert!(adiab_eta_equals_gamma2_witness());
    // 4. Energy conservation per cycle
    assert!(energy_ratio_identity());
    // 5. TOPS/W lift positive ≥ 2.5%
    assert!(w45_to_w46_lift_at_least_2_5pct());
    // Verify TOPS/W constants
    assert!(TOPS_W_W46_POST > TOPS_W_W45_POST);
    assert_eq!(TOPS_W_W46_POST, 1043);
    assert_eq!(TOPS_W_W45_POST, 1012);
}
