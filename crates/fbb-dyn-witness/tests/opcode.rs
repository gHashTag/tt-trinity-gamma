//! Wave-48 Lane SS'' — fbb-dyn-witness integration tests
//! 16 tests for OP_FBB_ACTIVE = 0xF2 (dynamic FBB of active path)
//! anchor phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877

use fbb_dyn_witness::{
    delay_reduction_in_band, distinct_from_adiab_rc, distinct_from_avs_reconf,
    distinct_from_dfs_gate, distinct_from_drowsy_ret, distinct_from_fbb_static,
    distinct_from_holo_mux, distinct_from_lut_npu, distinct_from_null_pe,
    distinct_from_rbb, distinct_from_sparse_mask, distinct_from_sparse_skip,
    distinct_from_spec_exit, distinct_from_stoch_round, distinct_from_subth_clk,
    distinct_from_tenet, distinct_from_tom, distinct_from_wl_boost, fclk_scale_capped,
    gamma4_canonical, leak_overhead_capped, net_delay_save_floor, op_in_extended_bank,
    sacred_rom_count_unchanged, symmetric_magnitude_with_rbb, tops_w_lift_at_least_1pt5pct,
    v_bs_derived_from_gamma4, v_bs_positive, v_bs_within_band, FbbActiveCtrl,
    DELAY_RED_CENTER_BPS, DELAY_RED_HI_BPS, DELAY_RED_LO_BPS, FCLK_SCALE_MAX_BPS,
    GAMMA4_BPS, LEAK_OVH_MAX_BPS, NET_DELAY_SAVE_MIN_BPS, OP_FBB_ACTIVE, OP_FBB_STATIC,
    OP_RBB, TOPS_W_POST, TOPS_W_PRE, V_BS_DECIMV, V_BS_DECIMV_HI, V_BS_DECIMV_LO,
};

#[test]
fn t01_opcode_encoding() {
    // OP_FBB_ACTIVE encodes to 0xF2 = 242
    assert_eq!(OP_FBB_ACTIVE, 0xF2);
    assert_eq!(OP_FBB_ACTIVE, 242);
}

#[test]
fn t02_v_bs_positive_sign() {
    // The defining property: V_BS is positive (distinct from W47 RBB negative)
    assert!(v_bs_positive());
    assert!(V_BS_DECIMV > 0);
}

#[test]
fn t03_v_bs_within_band() {
    // V_BS_DECIMV in [+10, +50] deci-mV (i.e. +1.0 to +5.0 mV)
    assert!(v_bs_within_band());
    assert_eq!(V_BS_DECIMV_LO, 10);
    assert_eq!(V_BS_DECIMV_HI, 50);
    assert_eq!(V_BS_DECIMV, 25); // canonical center
}

#[test]
fn t04_v_bs_derived_from_gamma4() {
    // |V_BS| = V_DD * gamma^4 derivation within ±1 deci-mV
    assert!(v_bs_derived_from_gamma4());
    assert!(gamma4_canonical());
    assert_eq!(GAMMA4_BPS, 31);
}

#[test]
fn t05_delay_reduction_band() {
    // Delay reduction must lie in [800, 1800] bps (8%..18%)
    assert!(delay_reduction_in_band(DELAY_RED_CENTER_BPS));
    assert!(delay_reduction_in_band(DELAY_RED_LO_BPS));
    assert!(delay_reduction_in_band(DELAY_RED_HI_BPS));
    assert!(!delay_reduction_in_band(799)); // below floor
    assert!(!delay_reduction_in_band(1801)); // above ceiling
    assert_eq!(DELAY_RED_CENTER_BPS, 1200); // 12% canonical center
}

#[test]
fn t06_leak_overhead_cap() {
    // Leakage overhead at most 800 bps (8% — R7 floor)
    assert!(leak_overhead_capped(0));
    assert!(leak_overhead_capped(LEAK_OVH_MAX_BPS));
    assert!(leak_overhead_capped(600)); // canonical operating point
    assert!(!leak_overhead_capped(801));
    assert_eq!(LEAK_OVH_MAX_BPS, 800);
}

#[test]
fn t07_net_delay_save_floor() {
    // Net delay save floor >= 800 bps (8%)
    assert!(net_delay_save_floor(NET_DELAY_SAVE_MIN_BPS));
    assert!(net_delay_save_floor(900));
    assert!(!net_delay_save_floor(799));
    assert_eq!(NET_DELAY_SAVE_MIN_BPS, 800);
}

#[test]
fn t08_fclk_scale_cap() {
    // f_clk scaling cap <= 600 bps (6%)
    assert!(fclk_scale_capped(0));
    assert!(fclk_scale_capped(FCLK_SCALE_MAX_BPS));
    assert!(fclk_scale_capped(400)); // canonical operating point
    assert!(!fclk_scale_capped(601));
    assert_eq!(FCLK_SCALE_MAX_BPS, 600);
}

#[test]
fn t09_tops_w_lift_at_least_1pt5pct() {
    // TOPS/W projection 1063 -> 1083 (+1.881%, >= 1.5%)
    assert!(tops_w_lift_at_least_1pt5pct());
    assert_eq!(TOPS_W_PRE, 1063);
    assert_eq!(TOPS_W_POST, 1083);
    // Manual verification: 1000 * 20 = 20000 >= 15 * 1063 = 15945 ✓
    assert!(1000 * (TOPS_W_POST - TOPS_W_PRE) >= 15 * TOPS_W_PRE);
    // Compute actual lift bps: 20*1000/1063 ≈ 18 bps absolute, but our R7 floor
    // is the 1.5% relative form proved above.
    let lift_bps = FbbActiveCtrl::tops_w_lift_bps();
    assert!(lift_bps >= 15, "Expected lift >= 15 bps relative, got {}", lift_bps);
}

#[test]
fn t10_symmetric_magnitude_with_rbb() {
    // |V_BS_FBB_ACTIVE| = |V_BS_RBB| = 25 deci-mV (cross-wave symmetry)
    assert!(symmetric_magnitude_with_rbb());
    // OP codes differ but magnitudes match
    assert_ne!(OP_FBB_ACTIVE, OP_RBB);
    assert_eq!(V_BS_DECIMV.unsigned_abs(), 25);
}

#[test]
fn t11_distinct_from_w47_w46_w45_w44() {
    // The four most-recent waves all have distinct opcodes from W48
    assert!(distinct_from_rbb()); // W47 0xF1
    assert!(distinct_from_adiab_rc()); // W46 0xF0
    assert!(distinct_from_wl_boost()); // W45 0xEF
    assert!(distinct_from_fbb_static()); // W44 0xEE — CRITICAL: dynamic FBB != static FBB
    assert_ne!(OP_FBB_ACTIVE, OP_FBB_STATIC);
}

#[test]
fn t12_distinct_from_all_w36_to_w43_opcodes() {
    // 13 distinctness witnesses for the older opcodes
    assert!(distinct_from_sparse_mask());
    assert!(distinct_from_drowsy_ret());
    assert!(distinct_from_spec_exit());
    assert!(distinct_from_null_pe());
    assert!(distinct_from_stoch_round());
    assert!(distinct_from_sparse_skip());
    assert!(distinct_from_dfs_gate());
    assert!(distinct_from_holo_mux());
    assert!(distinct_from_subth_clk());
    assert!(distinct_from_avs_reconf());
    assert!(distinct_from_lut_npu());
    assert!(distinct_from_tom());
    assert!(distinct_from_tenet());
}

#[test]
fn t13_op_in_extended_bank() {
    // OP_FBB_ACTIVE lies in extended sacred bank 0xD0..0xFF (32-slot ceremony, W47 R18)
    assert!(op_in_extended_bank());
    assert!(OP_FBB_ACTIVE >= 0xD0);
    assert!(OP_FBB_ACTIVE <= 0xFF);
}

#[test]
fn t14_r18_sacred_rom_count_unchanged() {
    // R18 LAYER-FROZEN: Sacred ROM stays at 75 cells. gamma^4 inherited
    // from B007^2 (W45) — NO new cell added by W47 or W48.
    assert!(sacred_rom_count_unchanged());
}

#[test]
fn t15_ctrl_step_under_fbb_active_opcode() {
    // Under OP_FBB_ACTIVE the controller charges to canonical operating point.
    let mut ctrl = FbbActiveCtrl::new();
    ctrl.step(OP_FBB_ACTIVE);
    assert!(ctrl.enabled);
    assert_eq!(ctrl.v_bs_decimv, V_BS_DECIMV); // +25
    assert_eq!(ctrl.delay_red_bps, DELAY_RED_CENTER_BPS); // 1200
    assert!(leak_overhead_capped(ctrl.leak_ovh_bps));
    assert!(fclk_scale_capped(ctrl.fclk_scale_bps));
    // Net = 1200 - 400 = 800 >= floor 800 ✓
    let net = ctrl.net_delay_save_bps();
    assert!(net_delay_save_floor(net), "net={} < floor={}", net, NET_DELAY_SAVE_MIN_BPS);
}

#[test]
fn t16_ctrl_step_under_other_opcodes_is_off() {
    // Under any non-OP_FBB_ACTIVE opcode the controller is off (composite invariant).
    let mut ctrl = FbbActiveCtrl::new();
    for op in [OP_RBB, OP_FBB_STATIC, 0xE1, 0xEE, 0xF0, 0x00, 0xFF] {
        ctrl.step(op);
        assert!(!ctrl.enabled, "ctrl should be off for op=0x{:02X}", op);
        assert_eq!(ctrl.v_bs_decimv, 0);
        assert_eq!(ctrl.delay_red_bps, 0);
    }
}
