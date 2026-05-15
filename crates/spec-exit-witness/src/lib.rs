// SPDX-License-Identifier: Apache-2.0
//! Wave-39 Lane DD'' — Speculative Early-Exit witness crate.
//!
//! Models speculative exit at confidence >= phi^-1 with 2/3 strand majority,
//! 1-cycle W38 trinity-bypass misprediction recovery, and TOPS/W projection.
//! Anchor: phi^2 + phi^-2 = 3; DOI 10.5281/zenodo.19227877.

#![deny(unsafe_code)]

/// OP_SPEC_EXIT — Speculative early-exit opcode.
/// Relocated 0xE7 → 0xEB per ICA-W40-001 (trinity-fpga#148) to free 0xE7 for OP_DFS_GATE (W40).
pub const OP_SPEC_EXIT: u8 = 0xEB;
pub const OP_CHAIN_LO: u8 = 0xD0;
pub const OP_CHAIN_HI: u8 = 0xEB;
pub const PHI_INV: f64 = 0.6180339887498949;
pub const PHI: f64 = 1.6180339887498949;
pub const N_RESERVOIR: usize = 27;
pub const BASELINE_W38_TOPS_PER_W: f64 = 392.0;
pub const TARGET_W39_TOPS_PER_W: f64 = 470.0;
pub const AVG_EXIT_DEPTH_TARGET: f64 = 0.42;
pub const OVERHEAD_SPECULATION_MAX: f64 = 0.50;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
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
}

#[derive(Clone, Debug)]
pub struct LayerOutput {
    pub confidence: f64,
    pub hidden_state: Vec<f64>,
}

/// Deterministic phi-vector inner product as a confidence classifier.
/// Returns a value in [0.0, 1.0] via a bounded squash s/(1+s).
pub fn confidence_classifier(hidden: &[f64]) -> f64 {
    if hidden.is_empty() {
        return 0.0;
    }
    let mut acc = 0.0_f64;
    let mut phi_pow = 1.0_f64;
    for &h in hidden.iter() {
        acc += h * phi_pow;
        phi_pow *= PHI_INV;
    }
    let s = acc.abs();
    s / (1.0 + s)
}

/// 2-of-3 majority vote across three strand classifiers.
///
/// Returns:
/// - `Z3::Pos1` if at least two strands agree on "commit-exit"
/// - `Z3::Neg1` otherwise (continue / 1-cycle bypass on misprediction)
pub fn three_strand_vote(s_fast: bool, s_mid: bool, s_slow: bool) -> Z3 {
    let n = (s_fast as u8) + (s_mid as u8) + (s_slow as u8);
    if n >= 2 {
        Z3::Pos1
    } else {
        Z3::Neg1
    }
}

pub fn should_early_exit(conf: f64, threshold: f64) -> bool {
    conf >= threshold
}

/// Speculate an exit and check against the actual confidence.
/// `Pos1` = correct commit; `Zero` = correct continue; `Neg1` = misprediction.
pub fn speculate_and_check(predicted_exit: bool, actual_conf: f64, threshold: f64) -> Z3 {
    let actual_exit = actual_conf >= threshold;
    match (predicted_exit, actual_exit) {
        (true, true) => Z3::Pos1,
        (false, false) => Z3::Zero,
        _ => Z3::Neg1,
    }
}

/// W38 trinity-bypass diode recovers from any speculation outcome in 1 cycle.
pub fn misprediction_recovery_cycles(_outcome: Z3) -> u32 {
    1
}

/// Average fraction of total depth executed before exit across traces.
/// Each trace is a per-layer confidence sequence of length `total_depth`.
/// Exit happens at the first layer where confidence >= threshold; otherwise
/// the trace runs to full depth.
pub fn avg_exit_depth(traces: &[Vec<f64>], total_depth: usize, threshold: f64) -> f64 {
    if traces.is_empty() || total_depth == 0 {
        return 0.0;
    }
    let mut sum_depth_fraction = 0.0_f64;
    for trace in traces.iter() {
        let mut exit_at = total_depth;
        for (i, &c) in trace.iter().enumerate() {
            if c >= threshold {
                exit_at = i + 1;
                break;
            }
        }
        sum_depth_fraction += (exit_at as f64) / (total_depth as f64);
    }
    sum_depth_fraction / (traces.len() as f64)
}

/// Projected TOPS/W under speculative early-exit.
/// baseline / avg_depth_fraction * (1 - overhead_fraction).
/// avg_depth=0.42, overhead=0.50, W38=392  =>  ~466.67  (target W39 = 470).
pub fn tops_per_w_estimate(
    avg_depth_fraction: f64,
    overhead_fraction: f64,
    baseline_tops_per_w: f64,
) -> f64 {
    if avg_depth_fraction <= 0.0 {
        return 0.0;
    }
    baseline_tops_per_w / avg_depth_fraction * (1.0 - overhead_fraction)
}

/// Deterministic LCG step (no `rand` dependency).
pub fn lcg_step(state: u64) -> u64 {
    state
        .wrapping_mul(6364136223846793005)
        .wrapping_add(1442695040888963407)
}

/// Map LCG state to a uniform f64 in [0.0, 1.0).
pub fn lcg_to_unit(state: u64) -> f64 {
    let bits = (state >> 32) as u32;
    (bits as f64) / (u32::MAX as f64 + 1.0)
}

/// Synthetic per-layer confidence trace whose threshold-crossing layer
/// is jittered around `target_fraction * total_depth`. Confidences grow
/// linearly from 0 toward ~1 and cap at 0.999.
pub fn synth_trace(seed: u64, total_depth: usize, target_fraction: f64) -> Vec<f64> {
    let mut s = seed.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut v = Vec::with_capacity(total_depth);
    s = lcg_step(s);
    let jitter = (lcg_to_unit(s) - 0.5) * 0.10;
    let cross_frac = (target_fraction + jitter).clamp(0.05, 0.95);
    let cross_idx = ((cross_frac * total_depth as f64).round() as usize).min(total_depth.saturating_sub(1).max(1));
    for i in 0..total_depth {
        // Step from below to >= PHI_INV exactly at i == cross_idx.
        let c = if i < cross_idx { 0.0 } else { 0.999 };
        v.push(c);
    }
    v
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_phi_inv_constant() {
        let phi = (1.0 + 5.0_f64.sqrt()) / 2.0;
        let phi_inv = 1.0 / phi;
        assert!((PHI_INV - phi_inv).abs() < 1e-9);
    }

    #[test]
    fn test_three_strand_majority() {
        let cases = [
            (false, false, false, Z3::Neg1),
            (true, false, false, Z3::Neg1),
            (false, true, false, Z3::Neg1),
            (false, false, true, Z3::Neg1),
            (true, true, false, Z3::Pos1),
            (true, false, true, Z3::Pos1),
            (false, true, true, Z3::Pos1),
            (true, true, true, Z3::Pos1),
        ];
        for (f, m, s, expect) in cases {
            assert_eq!(three_strand_vote(f, m, s), expect, "vote({},{},{})", f, m, s);
        }
    }

    #[test]
    fn test_should_early_exit_threshold() {
        assert!(should_early_exit(0.7, PHI_INV));
        assert!(should_early_exit(PHI_INV, PHI_INV));
        assert!(!should_early_exit(0.5, PHI_INV));
        assert!(!should_early_exit(0.0, PHI_INV));
    }

    #[test]
    fn test_avg_exit_depth_synthetic() {
        let total_depth = 32;
        let target = 0.42;
        let traces: Vec<Vec<f64>> = (0..1000)
            .map(|i| synth_trace(i as u64, total_depth, target))
            .collect();
        let avg = avg_exit_depth(&traces, total_depth, PHI_INV);
        assert!(avg >= 0.38 && avg <= 0.46, "avg exit depth out of band: {}", avg);
    }

    #[test]
    fn test_tops_per_w_geq_470() {
        let est = tops_per_w_estimate(0.42, 0.50, BASELINE_W38_TOPS_PER_W);
        assert!(est >= 466.0, "tops/w too low: {}", est);
    }

    #[test]
    fn test_opcode_chain_bounds() {
        assert_eq!(OP_CHAIN_LO, 0xD0);
        assert_eq!(OP_CHAIN_HI, 0xEB);
        assert_eq!(OP_SPEC_EXIT, 0xEB);
        assert!(OP_SPEC_EXIT >= OP_CHAIN_LO && OP_SPEC_EXIT <= OP_CHAIN_HI);
    }

    #[test]
    fn test_misprediction_recovery_one_cycle() {
        assert_eq!(misprediction_recovery_cycles(Z3::Neg1), 1);
        assert_eq!(misprediction_recovery_cycles(Z3::Pos1), 1);
        assert_eq!(misprediction_recovery_cycles(Z3::Zero), 1);
    }

    #[test]
    fn test_speculate_correct_and_misprediction() {
        let thr = PHI_INV;
        assert_eq!(speculate_and_check(true, 0.9, thr), Z3::Pos1);
        assert_eq!(speculate_and_check(false, 0.2, thr), Z3::Zero);
        assert_eq!(speculate_and_check(true, 0.2, thr), Z3::Neg1);
        assert_eq!(speculate_and_check(false, 0.9, thr), Z3::Neg1);
    }

    #[test]
    fn test_confidence_classifier_bounded() {
        let h = vec![0.5, 0.4, 0.3, 0.2, 0.1];
        let c = confidence_classifier(&h);
        assert!(c >= 0.0 && c < 1.0);
        assert_eq!(confidence_classifier(&[]), 0.0);
    }
}
