use subth_witness::*;

#[test]
fn test_v_island_0_30() {
    assert_eq!(V_ISLAND, 0.30);
}

#[test]
fn test_pe_count_1296() {
    assert_eq!(PE_COUNT, 1296);
}

#[test]
fn test_pe_count_is_6_to_4() {
    assert!(pe_count_is_sixth_fourth());
}

#[test]
fn test_n_islands_times_pe() {
    assert_eq!(n_islands_times_pe_per_island(), 1296);
    assert_eq!(48 * 27, 1296);
}

#[test]
fn test_three_freq_gcd_100() {
    assert_eq!(gcd_three(400, 300, 200), 100);
}

#[test]
fn test_three_freq_sum_900() {
    assert_eq!(strand_freq_sum_mhz(), 900);
}

#[test]
fn test_energy_ratio_quadratic() {
    let ratio = w37_energy_savings();
    // (0.30/0.45)^2 = (2/3)^2 = 4/9 ≈ 0.4444
    assert!((ratio - 4.0 / 9.0).abs() < 1e-10, "ratio was {}", ratio);
}

#[test]
fn test_meets_target() {
    assert!(meets_w37_target(), "tops_w_subth()={} < target={}", tops_w_subth(), TOPS_W_W37_TARGET);
}

#[test]
fn test_trinity_voltage() {
    assert!(trinity_voltage_check());
}
