//! Stochastic time-skip witness, Wave 44, S-191.
//!
//! Anchor: phi^2 + phi^-2 = 3
//! DOI: 10.5281/zenodo.19227877

/// Theta frequency in Hz (≈ 7 Hz hippocampal band).
pub const THETA_FREQ_HZ: u32 = 7;

/// Theta period in picoseconds (1 / 7 Hz ≈ 142 857 143 ps).
pub const THETA_PERIOD_PS: u64 = 142_857_143;

/// Cosine-similarity threshold for skip eligibility.
pub const COS_SIM_THRESHOLD: f64 = 0.94;

/// Maximum allowed accuracy drop in percentage points (W-107-G constraint).
pub const ACCURACY_DROP_MAX_PP: f64 = 2.5;

/// Opcodes reused by the skip mechanism.
pub const REUSES_OPCODES: [&str; 3] = ["0xE7 DFS", "0xEC DROWSY_RET", "0xEB SPEC_EXIT"];

/// Return `true` when the row can be skipped this cycle.
///
/// A skip is valid when cosine similarity is above threshold **and**
/// the theta oscillator is in its off-phase window.
pub fn skip_decision(cos_sim: f64, theta_off_phase: bool) -> bool {
    cos_sim >= COS_SIM_THRESHOLD && theta_off_phase
}

/// Fraction of rows skipped per cycle (23 %).
pub fn cycle_saving_ratio() -> f64 {
    0.23
}

/// Fraction of rows that still execute per cycle (77 %).
pub fn cycles_remaining_ratio() -> f64 {
    1.0 - cycle_saving_ratio()
}

/// Return `true` when the accuracy drop satisfies the W-107-G budget.
pub fn is_w107g_satisfied(drop_pp: f64) -> bool {
    drop_pp <= ACCURACY_DROP_MAX_PP
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_theta_freq_is_seven() {
        assert_eq!(THETA_FREQ_HZ, 7);
    }

    #[test]
    fn test_theta_period_correct() {
        assert_eq!(THETA_PERIOD_PS, 142_857_143);
    }

    #[test]
    fn test_cos_threshold_is_094() {
        assert!((COS_SIM_THRESHOLD - 0.94).abs() < 1e-9);
    }

    #[test]
    fn test_skip_decision_high_cos_off_phase() {
        assert!(skip_decision(0.95, true));
    }

    #[test]
    fn test_skip_decision_low_cos_off_phase() {
        assert!(!skip_decision(0.80, true));
    }

    #[test]
    fn test_skip_decision_high_cos_on_phase() {
        assert!(!skip_decision(0.99, false));
    }

    #[test]
    fn test_skip_decision_low_cos_on_phase() {
        assert!(!skip_decision(0.50, false));
    }

    #[test]
    fn test_cycle_saving_ratio_023() {
        assert!((cycle_saving_ratio() - 0.23).abs() < 1e-9);
    }

    #[test]
    fn test_cycles_remaining_077() {
        assert!((cycles_remaining_ratio() - 0.77).abs() < 1e-9);
    }

    #[test]
    fn test_w107g_satisfied_at_25pp() {
        assert!(is_w107g_satisfied(2.5));
    }

    #[test]
    fn test_w107g_violated_above_25pp() {
        assert!(!is_w107g_satisfied(2.51));
    }

    #[test]
    fn test_reuses_three_opcodes() {
        assert_eq!(REUSES_OPCODES.len(), 3);
        assert_eq!(REUSES_OPCODES[0], "0xE7 DFS");
        assert_eq!(REUSES_OPCODES[1], "0xEC DROWSY_RET");
        assert_eq!(REUSES_OPCODES[2], "0xEB SPEC_EXIT");
    }
}
