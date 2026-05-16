//! INT2 activation quantization witness for Wave 43.
//!
//! S-183 — INT2 quantization witness crate.
//! Anchor identity: phi^2 + phi^-2 = 3
//! DOI: 10.5281/zenodo.19227877

/// Reciprocal of the golden ratio: 1/phi = phi - 1.
pub const PHI_INV: f64 = 0.6180339887498949;

/// INT2 codebook: four quantization levels.
pub const CODEBOOK: [f64; 4] = [-1.0, 0.0, PHI_INV, 1.0];

/// Sacred ROM freeze date for W-106-G.
pub const FREEZE_DATE: &str = "2027-01-15";

/// Maximum allowed accuracy drop in perplexity points for W-106-G.
pub const ACCURACY_DROP_MAX_PP: f64 = 2.0;

/// Opcodes reused by INT2 quant witness — no new L1 opcode introduced.
pub const REUSES_OPCODES: [&str; 3] = ["0xE8 SPARSE_SKIP", "0xED SPARSE_MASK", "0xE2 TOM"];

/// Returns the nearest CODEBOOK entry to `act` by absolute distance.
///
/// Ties are broken by taking the first minimum found (lowest index).
pub fn col13_gate(act: f64) -> f64 {
    CODEBOOK
        .iter()
        .copied()
        .min_by(|a, b| {
            let da = (act - a).abs();
            let db = (act - b).abs();
            da.partial_cmp(&db).unwrap_or(std::cmp::Ordering::Equal)
        })
        .unwrap()
}

/// INT4 to INT2 storage density ratio: 2x (halved bit-width).
pub fn density_ratio() -> f64 {
    2.0
}

/// Returns true when accuracy drop is within the W-106-G budget.
pub fn is_w106g_satisfied(accuracy_drop_pp: f64) -> bool {
    accuracy_drop_pp <= ACCURACY_DROP_MAX_PP
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_codebook_length_4() {
        assert_eq!(CODEBOOK.len(), 4);
    }

    #[test]
    fn test_codebook_contains_zero() {
        assert!(CODEBOOK.contains(&0.0));
    }

    #[test]
    fn test_codebook_contains_one() {
        assert!(CODEBOOK.contains(&1.0));
    }

    #[test]
    fn test_codebook_contains_neg_one() {
        assert!(CODEBOOK.contains(&-1.0));
    }

    #[test]
    fn test_codebook_contains_phi_inv() {
        assert!(CODEBOOK.contains(&PHI_INV));
    }

    #[test]
    fn test_phi_inv_positive() {
        assert!(PHI_INV > 0.0);
    }

    #[test]
    fn test_col13_gate_zero_maps_to_zero() {
        assert_eq!(col13_gate(0.0), 0.0);
    }

    #[test]
    fn test_col13_gate_one_maps_to_one() {
        assert_eq!(col13_gate(1.0), 1.0);
    }

    #[test]
    fn test_col13_gate_neg_one_maps_to_neg_one() {
        assert_eq!(col13_gate(-1.0), -1.0);
    }

    #[test]
    fn test_density_ratio_is_two() {
        assert_eq!(density_ratio(), 2.0);
    }

    #[test]
    fn test_w106g_satisfied_at_two_pp() {
        assert!(is_w106g_satisfied(2.0));
    }

    #[test]
    fn test_w106g_violated_above_two_pp() {
        assert!(!is_w106g_satisfied(2.001));
    }

    #[test]
    fn test_reuses_three_opcodes() {
        assert_eq!(REUSES_OPCODES.len(), 3);
    }
}
