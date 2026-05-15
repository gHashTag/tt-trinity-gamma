//! Integration tests for the AVS-48 witness crate.
//! Wave-36 Lane X''. Anchor: phi^2 + phi^-2 = 3.

use avs_witness::{
    is_trinity_aligned, ir_drop_ratio, meets_w36_target, strand_count,
    ETA_AVS, N_ISLANDS, TOPS_W_W35, TOPS_W_W36_TARGET, V_ISLAND, V_TOTAL,
};

/// The stack contains exactly 48 voltage islands.
#[test]
fn test_n_islands_is_48() {
    assert_eq!(N_ISLANDS, 48);
}

/// 48 is divisible by 3 — trinity alignment holds.
#[test]
fn test_trinity_aligned() {
    assert!(is_trinity_aligned(N_ISLANDS));
}

/// 48 islands / 16 per strand = 3 strands.
#[test]
fn test_strand_count_three() {
    assert_eq!(strand_count(N_ISLANDS), 3);
}

/// IR-drop ratio for N=48 is 1/2304 (= 1/48²).
#[test]
fn test_ir_drop_ratio_quadratic() {
    let expected = 1.0_f64 / 2304.0_f64; // 1 / 48^2
    let got = ir_drop_ratio(N_ISLANDS);
    assert!(
        (got - expected).abs() < 1e-15,
        "ir_drop_ratio(48) = {got}, expected {expected}"
    );
}

/// AVS-48 achieves ≥ 297 TOPS/W — Wave-36 target is met.
#[test]
fn test_w36_target_met() {
    assert!(
        meets_w36_target(),
        "AVS-48 must reach {} TOPS/W (target {})",
        avs_witness::tops_w_avs(TOPS_W_W35, ETA_AVS),
        TOPS_W_W36_TARGET
    );
}

/// Total stack voltage is exactly 21.6 V (48 × 0.45 V).
#[test]
fn test_v_total_21_6() {
    assert!(
        (V_TOTAL - 21.6_f64).abs() < 1e-9,
        "V_TOTAL = {V_TOTAL}, expected 21.6"
    );
}

/// V_ISLAND constant is 0.45 V.
#[test]
fn test_v_island_0_45() {
    assert!((V_ISLAND - 0.45_f64).abs() < 1e-15);
}

/// Efficiency η = 0.93.
#[test]
fn test_eta_avs_value() {
    assert!((ETA_AVS - 0.93_f64).abs() < 1e-15);
}

/// W35 baseline is 270 TOPS/W, W36 target is 297 TOPS/W (10% uplift).
#[test]
fn test_tops_w_targets() {
    assert!((TOPS_W_W35 - 270.0_f64).abs() < 1e-10);
    assert!((TOPS_W_W36_TARGET - 297.0_f64).abs() < 1e-10);
}

/// trinity_strands() should always return 3 for a 48-island stack.
#[test]
fn test_trinity_strands() {
    assert_eq!(avs_witness::trinity_strands(), 3);
}
