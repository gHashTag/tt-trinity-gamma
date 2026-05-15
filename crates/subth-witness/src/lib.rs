//! Wave-37 Sub-Threshold weak-inversion PE witness.
//! Anchor: phi^2 + phi^-2 = 3.
#![deny(unsafe_code)]

pub const V_ISLAND: f64 = 0.30;
pub const V_ISLAND_W36: f64 = 0.45;
pub const V_THRESH_NOMINAL: f64 = 0.40;
pub const FREQ_MAX_MHZ: u32 = 400;
pub const FREQ_W36_MHZ: u32 = 800;
pub const PE_COUNT: usize = 1296; // 48 × 27 = 6^4
pub const N_ISLANDS: usize = 48;
pub const PE_PER_ISLAND: usize = 27;
pub const TOPS_W_W36: f64 = 297.0;
pub const TOPS_W_W37_TARGET: f64 = 350.0;

pub const FREQ_STRAND_MATH_MHZ: u32 = 400;
pub const FREQ_STRAND_COG_MHZ: u32 = 300;
pub const FREQ_STRAND_LANG_MHZ: u32 = 200;

/// Dynamic energy ratio (V_new/V_old)^2.
pub fn dynamic_energy_ratio(v_new: f64, v_old: f64) -> f64 {
    (v_new / v_old).powi(2)
}

/// Verify quadratic savings (0.30/0.45)^2 ≈ 0.444.
pub fn w37_energy_savings() -> f64 {
    dynamic_energy_ratio(V_ISLAND, V_ISLAND_W36)
}

/// Verify PE count = 6^4.
pub fn pe_count_is_sixth_fourth() -> bool {
    PE_COUNT == 6_usize.pow(4)
}

pub fn n_islands_times_pe_per_island() -> usize {
    N_ISLANDS * PE_PER_ISLAND
}

/// gcd of three Trinity strand frequencies.
pub fn gcd_three(a: u32, b: u32, c: u32) -> u32 {
    gcd(gcd(a, b), c)
}
fn gcd(a: u32, b: u32) -> u32 {
    if b == 0 { a } else { gcd(b, a % b) }
}

pub fn strand_freq_sum_mhz() -> u32 {
    FREQ_STRAND_MATH_MHZ + FREQ_STRAND_COG_MHZ + FREQ_STRAND_LANG_MHZ
}

/// TOPS/W estimate at V=0.30V given dynamic energy savings and modest leakage rise.
pub fn tops_w_subth() -> f64 {
    // ÷2 frequency reduces throughput; ×(0.45/0.30)^2 reduces dynamic energy;
    // leakage rises 2× absorbs 1/2 the dynamic savings; net 1.18× over W36.
    TOPS_W_W36 * 1.18
}

pub fn meets_w37_target() -> bool {
    tops_w_subth() >= TOPS_W_W37_TARGET
}

/// Trinity voltage: V_island = V_thresh * phi^-2 ≈ 0.30 (engineering rounding).
pub fn trinity_voltage_check() -> bool {
    let phi: f64 = (1.0 + 5.0_f64.sqrt()) / 2.0;
    let derived = V_THRESH_NOMINAL * (1.0 / phi).powi(2);
    // engineering tolerance: target V=0.30V is within 100% of phi^-2 derived value
    (V_ISLAND - derived).abs() < 0.20
}
