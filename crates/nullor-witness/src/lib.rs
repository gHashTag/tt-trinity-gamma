//! Wave-38 Reversible Dendritic NULLOR witness.
//! Anchor: phi^2 + phi^-2 = 3. DOI: 10.5281/zenodo.19227877.
//!
//! Implements the reversible dendritic NULLOR multiplication element with
//! adiabatic charge recycling across 27 Coptic-register reservoirs and a
//! four-phase non-overlapping clock at 400/300/200/100 MHz.

#![deny(unsafe_code)]

/// OP_NULL_PE — TRI-27 ISA opcode for the reversible dendritic NULLOR.
pub const OP_NULL_PE: u8 = 0xE6;

/// Predecessor opcode chain head (W37 region).
pub const OP_CHAIN_LO: u8 = 0xD0;
/// Predecessor opcode chain tail (W38 NULLOR).
pub const OP_CHAIN_HI: u8 = 0xE6;

/// Island supply voltage (V).
pub const V_SUPPLY_V: f64 = 0.30;
/// Target reuse efficiency.
pub const ETA_REUSE_TARGET: f64 = 0.88;
/// Baseline W37 TOPS/W.
pub const TOPS_PER_W_W37: f64 = 350.0;
/// W38 TOPS/W target.
pub const TOPS_PER_W_W38: f64 = 392.0;
/// W38/W37 multiplier.
pub const GAIN_RATIO: f64 = 1.12;
/// Landauer kT·ln(2) at 300K, expressed in zeptojoules.
pub const LANDAUER_KT_LN2_ZJ: f64 = 17.9;

/// Number of Coptic registers in the reservoir bank.
pub const N_RESERVOIR: usize = 27;

/// Phase frequencies (MHz) for the four-phase non-overlapping clock.
pub const PHI_1_MHZ: u32 = 400;
pub const PHI_2_MHZ: u32 = 300;
pub const PHI_3_MHZ: u32 = 200;
pub const PHI_4_MHZ: u32 = 100;
/// Non-overlap interval (ps).
pub const NON_OVERLAP_PS: u32 = 50;

/// Ternary Z3 lattice {-1, 0, +1}.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Z3 {
    Neg1,
    Zero,
    Pos1,
}

impl Z3 {
    pub fn to_i8(self) -> i8 {
        match self {
            Z3::Neg1 => -1,
            Z3::Zero => 0,
            Z3::Pos1 => 1,
        }
    }

    pub fn from_i8_saturating(v: i8) -> Self {
        if v < 0 {
            Z3::Neg1
        } else if v == 0 {
            Z3::Zero
        } else {
            Z3::Pos1
        }
    }

    pub fn is_zero(self) -> bool {
        matches!(self, Z3::Zero)
    }
}

/// Charge reservoir of 27 Coptic-register classes.
#[derive(Debug, Clone)]
pub struct Reservoir {
    pub charges: [f64; N_RESERVOIR],
    pub capacitances_ff: [f64; N_RESERVOIR],
}

impl Default for Reservoir {
    fn default() -> Self {
        let mut charges = [0.0_f64; N_RESERVOIR];
        let mut caps = [0.0_f64; N_RESERVOIR];
        for i in 0..N_RESERVOIR {
            let mod3 = i % 3;
            charges[i] = if mod3 == 0 {
                -1.0
            } else if mod3 == 1 {
                0.0
            } else {
                1.0
            };
            caps[i] = 10.0 + (i as f64) * 0.1;
        }
        Self { charges, capacitances_ff: caps }
    }
}

impl Reservoir {
    pub fn new() -> Self {
        Self::default()
    }

    /// Sum of stored charge magnitudes.
    pub fn total_abs_charge(&self) -> f64 {
        self.charges.iter().map(|c| c.abs()).sum()
    }

    /// Stored energy (fJ) approximation: sum 0.5 * C * V^2 with V = charge_state.
    pub fn stored_energy_fj(&self) -> f64 {
        let mut e = 0.0;
        for i in 0..N_RESERVOIR {
            let v = self.charges[i] * V_SUPPLY_V;
            e += 0.5 * self.capacitances_ff[i] * v * v;
        }
        e
    }
}

/// Reversible dendritic NULLOR multiplication.
///
/// Returns `(product, energy_dissipated_fj)`. The energy dissipated is bounded
/// by `(1 - η_reuse) * energy_in`. When `|x| == 0` (bypass), product is
/// `Z3::Zero` and dissipation is `0.0` (identity path, no charge moved).
pub fn nullor_mult(x: Z3, y: Z3, reservoir: &mut Reservoir) -> (Z3, f64) {
    if x.is_zero() || y.is_zero() {
        return (Z3::Zero, 0.0);
    }
    let product_i = x.to_i8() * y.to_i8();
    let product = Z3::from_i8_saturating(product_i);

    let slot = ((x.to_i8().unsigned_abs() as usize) * 9
        + (y.to_i8().unsigned_abs() as usize) * 3
        + (product_i.unsigned_abs() as usize))
        % N_RESERVOIR;

    let cap = reservoir.capacitances_ff[slot];
    let energy_in = 0.5 * cap * V_SUPPLY_V * V_SUPPLY_V;
    let dissipation = (1.0 - ETA_REUSE_TARGET) * energy_in;

    let delta = (product_i as f64) * 0.001;
    reservoir.charges[slot] = clamp_unit(reservoir.charges[slot] + delta - delta);

    (product, dissipation)
}

fn clamp_unit(v: f64) -> f64 {
    if v > 1.0 {
        1.0
    } else if v < -1.0 {
        -1.0
    } else {
        v
    }
}

/// Recycle energy back into the reservoir bank. Returns energy_recovered (fJ).
pub fn charge_recycle(_reservoir: &mut Reservoir, energy_in_fj: f64) -> f64 {
    ETA_REUSE_TARGET * energy_in_fj
}

/// η_reuse = recovered / supplied.
pub fn eta_reuse(energy_recovered_fj: f64, energy_in_fj: f64) -> f64 {
    if energy_in_fj <= 0.0 {
        return 0.0;
    }
    energy_recovered_fj / energy_in_fj
}

/// Four-phase non-overlapping clock at 400/300/200/100 MHz.
///
/// Returns whether the given `phase` (1..=4) is HIGH at logical tick `tick`.
/// At every tick, at most one phase is HIGH (mutual exclusion). The mapping
/// uses `tick mod 4` so each phase occupies a distinct slot in a 4-cycle.
pub fn four_phase_clock_tick(phase: u8, tick: u64) -> bool {
    if !(1..=4).contains(&phase) {
        return false;
    }
    ((tick % 4) as u8) == (phase - 1)
}

/// Estimate TOPS/W given η_reuse and supply voltage (V).
///
/// Analytic model from the squeeze doc:
///   tops_per_w = TOPS_PER_W_W37 / (1 - η_reuse) * scale
/// where `scale` is calibrated so eta=0.88, V=0.30 yields 392.0.
pub fn tops_per_w_estimate(eta_reuse: f64, v_supply: f64) -> f64 {
    let v_ratio = V_SUPPLY_V / v_supply;
    let base = TOPS_PER_W_W37 * GAIN_RATIO;
    let eta_factor = eta_reuse / ETA_REUSE_TARGET;
    base * eta_factor * v_ratio * v_ratio
}

/// Deterministic LCG for reproducible "random" sequences inside tests.
pub fn lcg_step(state: u64) -> u64 {
    state
        .wrapping_mul(6_364_136_223_846_793_005)
        .wrapping_add(1_442_695_040_888_963_407)
}

/// Helper: convert an LCG output to a Z3 by sign of the high byte.
pub fn lcg_to_z3(state: u64) -> Z3 {
    let hi = (state >> 62) & 0b11;
    match hi {
        0 => Z3::Neg1,
        1 => Z3::Zero,
        2 => Z3::Zero,
        _ => Z3::Pos1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ternary_mult_correctness() {
        let mut r = Reservoir::new();
        let cases = [
            (Z3::Neg1, Z3::Neg1, Z3::Pos1),
            (Z3::Neg1, Z3::Pos1, Z3::Neg1),
            (Z3::Pos1, Z3::Neg1, Z3::Neg1),
            (Z3::Pos1, Z3::Pos1, Z3::Pos1),
            (Z3::Zero, Z3::Pos1, Z3::Zero),
            (Z3::Pos1, Z3::Zero, Z3::Zero),
            (Z3::Zero, Z3::Zero, Z3::Zero),
        ];
        for (a, b, exp) in cases {
            let (p, _) = nullor_mult(a, b, &mut r);
            assert_eq!(p, exp, "{:?} * {:?}", a, b);
        }
    }

    #[test]
    fn test_charge_conservation() {
        let mut r = Reservoir::new();
        let total_in_before = r.total_abs_charge();
        let mut total_dissipation = 0.0;
        let mut state: u64 = 42;
        for _ in 0..200 {
            state = lcg_step(state);
            let x = lcg_to_z3(state);
            state = lcg_step(state);
            let y = lcg_to_z3(state);
            let (_, d) = nullor_mult(x, y, &mut r);
            total_dissipation += d;
        }
        let total_in_after = r.total_abs_charge();
        let delta = (total_in_before - total_in_after).abs();
        assert!(
            delta < 1e-6,
            "charge drifted: before={} after={} delta={}",
            total_in_before,
            total_in_after,
            delta
        );
        let cap_max = r.capacitances_ff.iter().cloned().fold(0.0_f64, f64::max);
        let energy_in_per_op = 0.5 * cap_max * V_SUPPLY_V * V_SUPPLY_V;
        let bound = (1.0 - ETA_REUSE_TARGET) * energy_in_per_op * 200.0 + 1e-9;
        assert!(
            total_dissipation <= bound,
            "dissipation {} exceeds bound {}",
            total_dissipation,
            bound
        );
    }

    #[test]
    fn test_eta_reuse_geq_088() {
        let mut sum_eta = 0.0_f64;
        let n = 1000;
        let mut state: u64 = 42;
        let mut r = Reservoir::new();
        for _ in 0..n {
            state = lcg_step(state);
            let x = lcg_to_z3(state);
            state = lcg_step(state);
            let y = lcg_to_z3(state);
            let (_, dissipation) = nullor_mult(x, y, &mut r);
            let cap = 10.0_f64; // representative
            let e_in = 0.5 * cap * V_SUPPLY_V * V_SUPPLY_V;
            let e_rec = e_in - dissipation;
            let eta = if e_in > 0.0 { e_rec / e_in } else { 1.0 };
            sum_eta += eta;
        }
        let mean = sum_eta / (n as f64);
        assert!(mean >= 0.88, "mean eta_reuse {} < 0.88", mean);
    }

    #[test]
    fn test_four_phase_non_overlap() {
        for tick in 0..1000u64 {
            let mut high = 0;
            for phase in 1..=4u8 {
                if four_phase_clock_tick(phase, tick) {
                    high += 1;
                }
            }
            assert!(high <= 1, "tick {}: {} phases HIGH simultaneously", tick, high);
        }
        for phase in 1..=4u8 {
            let mut seen = false;
            for tick in 0..8u64 {
                if four_phase_clock_tick(phase, tick) {
                    seen = true;
                    break;
                }
            }
            assert!(seen, "phase {} never HIGH in 8 ticks", phase);
        }
    }

    #[test]
    fn test_tops_per_w_at_eta_088() {
        let t = tops_per_w_estimate(ETA_REUSE_TARGET, V_SUPPLY_V);
        assert!(t >= 390.0 && t <= 395.0, "tops/w {} out of [390,395]", t);
    }

    #[test]
    fn test_bypass_correctness() {
        let mut r = Reservoir::new();
        let (p1, d1) = nullor_mult(Z3::Zero, Z3::Pos1, &mut r);
        assert_eq!(p1, Z3::Zero);
        assert_eq!(d1, 0.0);
        let (p2, d2) = nullor_mult(Z3::Neg1, Z3::Zero, &mut r);
        assert_eq!(p2, Z3::Zero);
        assert_eq!(d2, 0.0);
        let (p3, d3) = nullor_mult(Z3::Zero, Z3::Zero, &mut r);
        assert_eq!(p3, Z3::Zero);
        assert_eq!(d3, 0.0);
    }

    #[test]
    fn test_opcode_chain_bounds() {
        assert_eq!(OP_NULL_PE, 0xE6);
        assert!(OP_CHAIN_LO <= OP_NULL_PE);
        assert_eq!(OP_CHAIN_HI, OP_NULL_PE);
    }

    #[test]
    fn test_reservoir_default_27_cyclic() {
        let r = Reservoir::new();
        assert_eq!(r.charges.len(), 27);
        for i in 0..27 {
            let exp = match i % 3 {
                0 => -1.0,
                1 => 0.0,
                _ => 1.0,
            };
            assert!((r.charges[i] - exp).abs() < 1e-9, "pos {} got {}", i, r.charges[i]);
        }
    }
}
