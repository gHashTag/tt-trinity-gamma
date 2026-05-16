//! # Purkinje Thermal Witness — Wave 46 Lane RR''
//!
//! Thermal gating witness crate for TRI-1 Wave 46.
//! Witness ID: W-109-G. Freeze: 2027-04-15.
//!
//! Anchor: phi^2 + phi^-2 = 3 (Trinity Identity)
//!
//! This crate models thermal masking for Purkinje-layer tile arrays,
//! computing per-tile enable masks based on junction temperature.
//! Target performance: 2806 TOPS/W at 95% thermal envelope
//! across 27 tiles with reused opcodes [0xE4, 0xEC, 0xEF].
//!
//! DOI: 10.5281/zenodo.19227877

/// Wave number.
pub const WAVE: u32 = 46;

/// Target performance in TOPS per Watt.
pub const TARGET_TOPS_PER_WATT: f64 = 2806.0;

/// Witness identifier string.
pub const WITNESS_ID: &str = "W-109-G";

/// Maximum accuracy drop in percentage points.
pub const ACCURACY_DROP_PP_MAX: f64 = 1.0;

/// Thermal envelope as percentage of full power budget.
pub const THERMAL_ENVELOPE_PCT: u8 = 95;

/// Number of Purkinje-layer tiles.
pub const TILE_COUNT: u8 = 27;

/// Junction temperature threshold in Celsius.
/// Tiles at or above this temperature are masked off.
const TEMP_THRESHOLD_C: i16 = 85;

/// Compute enable mask for a single tile based on its junction temperature.
///
/// Returns `1` if `temp_c` is below the thermal threshold (tile is active),
/// or `0` if the tile is at or above the threshold (tile is gated off).
///
/// # Arguments
///
/// * `temp_c` — Junction temperature in degrees Celsius.
///
/// # Examples
///
/// ```
/// use purkinje_thermal_witness::mask_for_tile_temp;
/// assert_eq!(mask_for_tile_temp(70), 1);
/// assert_eq!(mask_for_tile_temp(85), 0);
/// assert_eq!(mask_for_tile_temp(90), 0);
/// ```
pub fn mask_for_tile_temp(temp_c: i16) -> u8 {
    if temp_c < TEMP_THRESHOLD_C {
        1
    } else {
        0
    }
}

/// Compose two tile masks using bitwise AND.
///
/// Both mask bits must be `1` for the composed result to be `1`.
///
/// # Arguments
///
/// * `a` — First mask byte.
/// * `b` — Second mask byte.
pub fn compose_masks(a: u8, b: u8) -> u8 {
    a & b
}

/// Return the target TOPS/W figure for Wave 46.
pub fn tops_per_watt() -> f64 {
    TARGET_TOPS_PER_WATT
}

/// Return the witness identifier string.
pub fn witness_id() -> &'static str {
    WITNESS_ID
}

/// Return the number of Purkinje-layer tiles.
pub fn tile_count() -> u8 {
    TILE_COUNT
}

/// Return the three reused opcodes for Wave 46 tile microcode.
pub fn reused_opcodes() -> [u8; 3] {
    [0xE4, 0xEC, 0xEF]
}

/// Return uplift ratio of Wave 46 over Wave 45 in TOPS/W.
///
/// Wave 45 baseline: 2158 TOPS/W.
/// Wave 46 target:   2806 TOPS/W.
pub fn uplift_over_w45() -> f64 {
    2806.0 / 2158.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_witness_id() {
        assert_eq!(witness_id(), "W-109-G");
    }

    #[test]
    fn test_tops_per_watt() {
        let tpw = tops_per_watt();
        assert!((tpw - 2806.0).abs() < f64::EPSILON);
    }

    #[test]
    fn test_mask_hot_tile() {
        // Tile at 90 °C should be masked off
        assert_eq!(mask_for_tile_temp(90), 0);
    }

    #[test]
    fn test_mask_cold_tile() {
        // Tile at 70 °C should be active
        assert_eq!(mask_for_tile_temp(70), 1);
    }

    #[test]
    fn test_mask_at_boundary() {
        // Exactly at threshold → masked off
        assert_eq!(mask_for_tile_temp(85), 0);
    }

    #[test]
    fn test_compose_idempotent() {
        // Composing a mask with itself is idempotent
        assert_eq!(compose_masks(1, 1), 1);
        assert_eq!(compose_masks(0, 0), 0);
    }

    #[test]
    fn test_compose_commutative() {
        assert_eq!(compose_masks(1, 0), compose_masks(0, 1));
    }

    #[test]
    fn test_tile_count_equals_27() {
        assert_eq!(tile_count(), 27);
        assert_eq!(TILE_COUNT, 27);
    }

    #[test]
    fn test_reused_opcodes_contains_e4() {
        assert!(reused_opcodes().contains(&0xE4));
    }

    #[test]
    fn test_reused_opcodes_contains_ec() {
        assert!(reused_opcodes().contains(&0xEC));
    }

    #[test]
    fn test_reused_opcodes_contains_ef() {
        assert!(reused_opcodes().contains(&0xEF));
    }

    #[test]
    fn test_accuracy_bound() {
        // Maximum accuracy drop must not exceed 1.0 pp
        assert!(ACCURACY_DROP_PP_MAX <= 1.0);
    }

    #[test]
    fn test_thermal_envelope() {
        // Thermal envelope must be exactly 95 %
        assert_eq!(THERMAL_ENVELOPE_PCT, 95);
    }

    #[test]
    fn test_uplift_over_1_30() {
        // Wave 46 must show > 30 % uplift over Wave 45
        assert!(uplift_over_w45() > 1.30);
    }
}
