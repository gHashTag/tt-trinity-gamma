// SPDX-License-Identifier: Apache-2.0
// Authors: Vasilev Dmitrii <admin@t27.ai>
//
// W-102-A — TENET Sparsity Runtime Witness
// L-DPC26 Wave-29 · Lane T''' (Triple-Prime)
//
// R7 falsifier for Lever #3: TENET sparsity-aware LUT.
// Mirrors Lane T' Coq tenet_no_star (gHashTag/t27 PR #644 @ 367a7ba64e),
// opcode OP_SPARSE_SKIP = 0xE1, Lemma tenet_no_star.
//
// R5-HONEST: all numeric constants are PRE-SILICON ESTIMATEs based on the
// BitNet b1.58 2B4T paper (arXiv:2504.12285) until silicon verdict 2026-10-15.

/// Minimum acceptable sparsity ratio for BitNet b1.58-3B workloads.
///
/// BitNet b1.58 2B4T reports ~30 % zero weights (arXiv:2504.12285).
/// The bound is set conservatively at 25 % to give silicon 5 pp of margin.
///
/// # Constitutional status
/// PRE-SILICON ESTIMATE — frozen 2026-08-15. Revisit after silicon verdict 2026-10-15.
pub const SPARSITY_LOWER_BOUND: f64 = 0.25; // PRE-SILICON ESTIMATE

/// Returns `true` iff `measured` satisfies the R7 sparsity bound.
///
/// Post-silicon this function is called with real RTL counters from the
/// `sparsity_skip` controller (Lane T). If the result is `false` the
/// W-102-A test FAILS → fail-stop per Wave-29 R7 policy.
#[inline]
pub fn meets_sparsity_bound(measured: f64) -> bool {
    measured >= SPARSITY_LOWER_BOUND
}

/// A single sparsity measurement recorded by the `sparsity_skip` RTL
/// controller during a BitNet b1.58-3B inference run.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SparsityMeasurement {
    /// Number of LUT lookups skipped due to OP_SPARSE_SKIP (opcode 0xE1).
    pub skip_count: u64,
    /// Total LUT lookups attempted (skipped + executed).
    pub total_lookups: u64,
}

impl SparsityMeasurement {
    /// Creates a new measurement.
    ///
    /// # Panics
    /// Panics if `total_lookups` is zero (division by zero).
    pub fn new(skip_count: u64, total_lookups: u64) -> Self {
        assert!(total_lookups > 0, "total_lookups must be > 0");
        Self {
            skip_count,
            total_lookups,
        }
    }

    /// Returns the fraction of lookups that were skipped.
    ///
    /// Value is in [0.0, 1.0].
    pub fn ratio(&self) -> f64 {
        self.skip_count as f64 / self.total_lookups as f64
    }
}

#[cfg(test)]
mod unit_tests {
    use super::*;

    #[test]
    fn meets_bound_at_threshold() {
        assert!(meets_sparsity_bound(0.25));
    }

    #[test]
    fn fails_below_threshold() {
        assert!(!meets_sparsity_bound(0.24));
    }

    #[test]
    fn ratio_calculation() {
        let m = SparsityMeasurement::new(300_000, 1_000_000);
        assert!((m.ratio() - 0.30).abs() < f64::EPSILON);
    }
}
