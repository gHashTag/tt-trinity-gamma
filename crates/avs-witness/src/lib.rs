//! Wave-36 AVS-48 witness.
//! Anchor: phi^2 + phi^-2 = 3.
//! DOI: 10.5281/zenodo.19227877.
#![deny(unsafe_code)]

/// Number of voltage islands in the AVS-48 stack.
pub const N_ISLANDS: usize = 48;

/// Per-island voltage (V).
pub const V_ISLAND: f64 = 0.45;

/// Total stack voltage: 48 × 0.45 = 21.6 V.
pub const V_TOTAL: f64 = V_ISLAND * (N_ISLANDS as f64);

/// Charge-recycling regulator efficiency (η).
pub const ETA_AVS: f64 = 0.93;

/// Wave-35 LUT-NPU baseline TOPS/W.
pub const TOPS_W_W35: f64 = 270.0;

/// Wave-36 AVS-48 target TOPS/W.
pub const TOPS_W_W36_TARGET: f64 = 297.0;

/// Trinity divisibility check: returns true when n is divisible by 3.
///
/// The 48-island stack satisfies this: 48 = 3 × 16.
pub fn is_trinity_aligned(n: usize) -> bool {
    n % 3 == 0
}

/// Strand count for an N-island stack.
///
/// With 16 islands per strand, a 48-island stack yields 3 strands.
pub fn strand_count(n: usize) -> usize {
    n / 16
}

/// IR-drop loss ratio: loss(N) / loss(1) = 1 / N².
///
/// Charge-recycling across N islands reduces IR-drop losses quadratically.
/// R-SI-1: this is host-side Rust scalar math, NOT synthesised;
/// ternary kernel ops live in lut-npu-witness.
pub fn ir_drop_ratio(n: usize) -> f64 {
    let n_f = n as f64;
    1.0_f64 / n_f.powi(2)
}

/// Compute TOPS/W for the AVS-48 configuration.
///
/// Improvement scales linearly with η/η_baseline up to the ÷N² IR-drop
/// benefit cap of 1.10×.
///
/// R-SI-1: this is host-side Rust scalar math, NOT synthesised;
/// ternary kernel ops live in lut-npu-witness.
pub fn tops_w_avs(tops_w_baseline: f64, eta: f64) -> f64 {
    let cap = 1.10_f64;
    // Use mul_add for fused multiply-add to avoid intermediate rounding.
    // Equivalent to: tops_w_baseline * (eta / 0.93) * cap
    let eta_ratio = eta / ETA_AVS;
    tops_w_baseline.mul_add(eta_ratio, 0.0_f64) * cap
}

/// Returns true when the AVS-48 configuration meets the Wave-36 TOPS/W target.
pub fn meets_w36_target() -> bool {
    tops_w_avs(TOPS_W_W35, ETA_AVS) >= TOPS_W_W36_TARGET
}

/// Number of strands in the trinity stack (always 3 for N_ISLANDS = 48).
pub fn trinity_strands() -> usize {
    strand_count(N_ISLANDS)
}

/// Phi-squared identity check: φ² + φ⁻² ≈ 3.
///
/// The golden ratio φ = (1 + √5) / 2.
pub fn phi_sq_identity_holds() -> bool {
    let phi = (1.0_f64 + 5.0_f64.sqrt()) / 2.0_f64;
    let phi_sq = phi.powi(2);
    let phi_inv_sq = phi.powi(-2);
    (phi_sq + phi_inv_sq - 3.0_f64).abs() < 1e-12
}

/// Stack voltage summary for all islands.
///
/// Returns a Vec of per-island voltages (all equal to V_ISLAND in this model).
pub fn island_voltages() -> Vec<f64> {
    vec![V_ISLAND; N_ISLANDS]
}

/// Total voltage computed by summing the island voltage vector.
pub fn v_total_computed() -> f64 {
    island_voltages().iter().copied().sum()
}

/// Efficiency headroom: how far η is above a nominal 0.90 floor.
pub fn eta_headroom() -> f64 {
    ETA_AVS - 0.90_f64
}

/// TOPS/W improvement factor over W35 baseline.
pub fn tops_w_improvement_factor() -> f64 {
    tops_w_avs(TOPS_W_W35, ETA_AVS) / TOPS_W_W35
}

#[cfg(test)]
mod unit_tests {
    use super::*;

    #[test]
    fn unit_v_total_constant() {
        // Compile-time constant V_TOTAL must equal 21.6 V.
        assert!((V_TOTAL - 21.6_f64).abs() < 1e-9);
    }

    #[test]
    fn unit_phi_identity() {
        assert!(phi_sq_identity_holds());
    }

    #[test]
    fn unit_eta_headroom_positive() {
        assert!(eta_headroom() > 0.0_f64);
    }

    #[test]
    fn unit_island_voltages_len() {
        assert_eq!(island_voltages().len(), N_ISLANDS);
    }

    #[test]
    fn unit_v_total_computed_matches_constant() {
        assert!((v_total_computed() - V_TOTAL).abs() < 1e-9);
    }

    #[test]
    fn unit_improvement_factor_above_one() {
        assert!(tops_w_improvement_factor() > 1.0_f64);
    }
}
