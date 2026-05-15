//! Wave-42 Lane II'' — STOCHASTIC ROUNDING witness
//! OP_STOCH_ROUND = 0xE9 — R-SI-1 unique sacred opcode
//! anchor phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877

/// Sacred opcode: stochastic rounding (Wave-42).
/// Distinct from all prior opcodes in the TRI-27 ISA chain.
pub const OP_STOCH_ROUND: u8 = 0xE9;

// Prior opcodes in the chain (for distinctness proofs)
pub const OP_SPARSE_SKIP: u8 = 0xE8;
pub const OP_DFS_GATE: u8 = 0xE7;
pub const OP_HOLO_MUX_X4: u8 = 0xE6;
pub const OP_SUBTH_CLK: u8 = 0xE5;
pub const OP_AVS_RECONF: u8 = 0xE4;
pub const OP_LUT_NPU: u8 = 0xE3;
pub const OP_TOM: u8 = 0xE2;
pub const OP_TENET: u8 = 0xE1;

/// Galois LFSR-32 with taps 0x80200003 (bits 32, 22, 2, 1).
///
/// Used as the entropy source for stochastic rounding decisions.
pub struct Lfsr32 {
    state: u32,
}

impl Lfsr32 {
    /// Create a new LFSR. If `seed == 0`, uses the default seed `0xACE1_ACE1`
    /// to avoid the all-zero absorbing state.
    pub fn new(seed: u32) -> Self {
        Self {
            state: if seed == 0 { 0xACE1_ACE1 } else { seed },
        }
    }

    /// Advance the LFSR by one step and return the new state.
    ///
    /// Galois taps 0x80200003: bits 32, 22, 2, 1.
    pub fn step(&mut self) -> u32 {
        let lsb = self.state & 1;
        self.state >>= 1;
        if lsb == 1 {
            self.state ^= 0x80200003;
        }
        self.state
    }
}

/// Stochastic rounding unit backed by a Galois LFSR-32.
///
/// For opcode `OP_STOCH_ROUND`, rounds `x_int + x_frac/16` to an integer
/// by drawing a 4-bit random threshold from the LFSR and comparing it to
/// the low nibble of `x_frac`. The result is unbiased in expectation.
pub struct StochRound {
    pub lfsr: Lfsr32,
}

impl StochRound {
    /// Construct a new `StochRound` with the given LFSR seed.
    pub fn new(seed: u32) -> Self {
        Self {
            lfsr: Lfsr32::new(seed),
        }
    }

    /// Perform one stochastic-rounding step.
    ///
    /// - If `opcode != OP_STOCH_ROUND`, passes `x_int` through unchanged.
    /// - Otherwise draws `r = lfsr.step() & 0xF` and returns
    ///   `x_int + 1` iff `r < (x_frac & 0xF)`, else `x_int`.
    pub fn round(&mut self, opcode: u8, x_int: i16, x_frac: u8) -> i16 {
        if opcode != OP_STOCH_ROUND {
            return x_int;
        }
        let r = (self.lfsr.step() & 0xF) as u8;
        if r < (x_frac & 0xF) {
            x_int + 1
        } else {
            x_int
        }
    }

    // ── Distinctness witnesses (one-liners) ─────────────────────────────────

    /// 0xE9 ≠ 0xE8 (OP_SPARSE_SKIP)
    pub fn distinct_from_sparse(&self) -> bool {
        OP_STOCH_ROUND != 0xE8
    }

    /// 0xE9 ≠ 0xE7 (OP_DFS_GATE)
    pub fn distinct_from_dfs(&self) -> bool {
        OP_STOCH_ROUND != 0xE7
    }

    /// 0xE9 ≠ 0xE6 (OP_HOLO_MUX_X4)
    pub fn distinct_from_holo_mux(&self) -> bool {
        OP_STOCH_ROUND != 0xE6
    }

    /// 0xE9 ≠ 0xE5 (OP_SUBTH_CLK)
    pub fn distinct_from_subth(&self) -> bool {
        OP_STOCH_ROUND != 0xE5
    }

    /// 0xE9 ≠ 0xE4 (OP_AVS_RECONF)
    pub fn distinct_from_avs_reconf(&self) -> bool {
        OP_STOCH_ROUND != 0xE4
    }

    /// 0xE9 ≠ 0xE3 (OP_LUT_NPU)
    pub fn distinct_from_lut_npu(&self) -> bool {
        OP_STOCH_ROUND != 0xE3
    }

    /// 0xE9 ≠ 0xE2 (OP_TOM)
    pub fn distinct_from_tom(&self) -> bool {
        OP_STOCH_ROUND != 0xE2
    }

    /// 0xE9 ≠ 0xE1 (OP_TENET)
    pub fn distinct_from_tenet(&self) -> bool {
        OP_STOCH_ROUND != 0xE1
    }
}
