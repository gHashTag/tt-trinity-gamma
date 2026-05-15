//! Wave-41 Lane GG'' — SPARSE-ACTIVATION GATING witness
//! OP_SPARSE_SKIP = 0xE8 — R-SI-1 unique sacred opcode
//! anchor phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877

/// Sacred opcode: sparse-activation skip gate (Wave-41).
/// Distinct from all prior opcodes in the TRI-27 ISA chain.
pub const OP_SPARSE_SKIP: u8 = 0xE8;

// Prior opcodes in the chain (for distinctness proofs)
pub const OP_DFS_GATE: u8 = 0xE7;
pub const OP_HOLO_MUX_X4: u8 = 0xE6;
pub const OP_SUBTH_CLK: u8 = 0xE5;
pub const OP_AVS_RECONF: u8 = 0xE4;
pub const OP_LUT_NPU: u8 = 0xE3;
pub const OP_TOM: u8 = 0xE2;
pub const OP_TENET: u8 = 0xE1;

/// Sparse-activation gate for Wave-41 SPARSE-ACTIVATION GATING.
///
/// `tau` encodes a threshold via a 3-bit exponent + 5-bit mantissa scheme:
///   decoded threshold = (tau & 0x1F) << ((tau >> 5) & 0x7)
///
/// `sparsity_cnt` tracks how many activations have been skipped.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SparseGate {
    /// Encoded threshold: 3-bit exp (bits 7..5) + 5-bit mantissa (bits 4..0).
    pub tau: u8,
    /// Running count of skipped (gated-out) activations.
    pub sparsity_cnt: u32,
}

impl SparseGate {
    /// Construct a new `SparseGate` with the given encoded threshold.
    /// `sparsity_cnt` starts at zero.
    pub fn new(tau: u8) -> Self {
        Self { tau, sparsity_cnt: 0 }
    }

    /// Decode the threshold: mantissa shifted left by exponent.
    ///
    /// `decoded = (tau & 0x1F) << ((tau >> 5) & 0x7)`
    pub fn tau_decoded(&self) -> u16 {
        let mantissa = (self.tau & 0x1F) as u16;
        let exp = ((self.tau >> 5) & 0x07) as u16;
        mantissa << exp
    }

    /// Decide whether to skip this activation.
    ///
    /// Returns `true` (skip) iff:
    ///   - `opcode == OP_SPARSE_SKIP`, AND
    ///   - `|activation| < tau_decoded()`, AND
    ///   - `topk_keep` is `false`.
    ///
    /// When returning `true`, increments `sparsity_cnt`.
    /// `topk_keep = true` forces the gate open (no skip), regardless of threshold.
    pub fn should_skip(&mut self, opcode: u8, activation: i16, topk_keep: bool) -> bool {
        if topk_keep {
            return false;
        }
        if opcode != OP_SPARSE_SKIP {
            return false;
        }
        let abs_act = activation.unsigned_abs() as u16;
        if abs_act < self.tau_decoded() {
            self.sparsity_cnt += 1;
            true
        } else {
            false
        }
    }

    // ── Distinctness witnesses (one-liners) ─────────────────────────────────

    /// 0xE8 ≠ 0xE7 (OP_DFS_GATE)
    pub fn distinct_from_dfs(&self) -> bool {
        OP_SPARSE_SKIP != 0xE7
    }

    /// 0xE8 ≠ 0xE6 (OP_HOLO_MUX_X4)
    pub fn distinct_from_holo_mux(&self) -> bool {
        OP_SPARSE_SKIP != 0xE6
    }

    /// 0xE8 ≠ 0xE5 (OP_SUBTH_CLK)
    pub fn distinct_from_subth(&self) -> bool {
        OP_SPARSE_SKIP != 0xE5
    }

    /// 0xE8 ≠ 0xE4 (OP_AVS_RECONF)
    pub fn distinct_from_avs(&self) -> bool {
        OP_SPARSE_SKIP != 0xE4
    }

    /// 0xE8 ≠ 0xE3 (OP_LUT_NPU)
    pub fn distinct_from_lut_npu(&self) -> bool {
        OP_SPARSE_SKIP != 0xE3
    }

    /// 0xE8 ≠ 0xE2 (OP_TOM)
    pub fn distinct_from_tom(&self) -> bool {
        OP_SPARSE_SKIP != 0xE2
    }

    /// 0xE8 ≠ 0xE1 (OP_TENET)
    pub fn distinct_from_tenet(&self) -> bool {
        OP_SPARSE_SKIP != 0xE1
    }

    /// 0xE8 ≠ 0xD0..=0xE0 (full lower range)
    pub fn distinct_from_lower_range(&self) -> bool {
        !(0xD0u8..=0xE0u8).contains(&OP_SPARSE_SKIP)
    }
}
