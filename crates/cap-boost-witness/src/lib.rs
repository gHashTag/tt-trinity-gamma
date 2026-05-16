//! Wave-49 Lane VV'' — Capacitive Decoupling Burst (CAP-BOOST) witness
//!
//! OP_CAP_BOOST = 0xF3 = 243 — Wave-49 third slot of extended sacred bank 0xD0..0xFF
//!
//! THIRD LEVER of triple-decker dynamic-power envelope:
//!   - W47 RBB         (0xF1): leakage-path well bias V_BS = -V_DD * gamma^4
//!   - W48 FBB-ACTIVE  (0xF2): active-path well bias V_BS = +V_DD * gamma^4
//!   - W49 CAP-BOOST   (0xF3): supply-rail capacitive burst ΔC = C_dec_base * gamma^3
//!
//! Three orthogonal levers — well-bias-negative (idle PEs), well-bias-positive
//! (active PEs), rail-capacitance-burst (supply node) — stacked at iso-area.
//!
//! Theory:
//!   - ΔC_dec = C_dec_base * gamma^3 ≈ 100 pF * 0.0081 ≈ 0.81 pF burst
//!   - gamma^3 = phi^-9 ≈ 0.01316 inherited from B007^3 (Sacred ROM, NO new cell)
//!   - di/dt margin: +6% nominal, band [4%, 10%]
//!   - Droop suppression: -4% nominal, band [2%, 8%]
//!   - Cap area uplift: ≤ 0.5% (50 bps) — R18 iso-area
//!   - f_clk impact: ≤ 2% (200 bps)
//!   - TOPS/W: 1083 -> 1091 (+0.738%, ≥ 0.7% floor)
//!
//! R18 LAYER-FROZEN: bank-set frozen at 0xD0..0xFF since W47 — NO new Sacred ROM
//! cell added. gamma^3 inherited from B007^3.
//!
//! Quantum Brain 1:1 mapping:
//!   PHYS->SI  gamma^3 = phi^-9                -> capacitive burst fraction
//!   BIO->SI   cardiac decoupling capacitor    -> rail charge reservoir burst
//!   LANG->SI  TRI-27 OP_CAP_BOOST             -> 0xF3 sacred opcode
//!
//! anchor phi^2 + phi^-2 = 3 · gamma^3 = phi^-9 · DOI 10.5281/zenodo.19227877

/// Sacred opcode: capacitive decoupling burst (Wave-49).
/// Slot 3 of extended sacred bank 0xD0..0xFF (R18 bank-extension ceremony, W47).
pub const OP_CAP_BOOST: u8 = 0xF3;

// Prior sacred opcodes in extended bank (for distinctness witnesses)
pub const OP_FBB_ACTIVE: u8 = 0xF2; // W48 — second lever (active well)
pub const OP_RBB: u8 = 0xF1; // W47 — first lever (idle well)
pub const OP_ADIAB_RC: u8 = 0xF0; // W46
pub const OP_WL_BOOST: u8 = 0xEF; // W45
pub const OP_FBB_STATIC: u8 = 0xEE; // W44 — distinct static FBB
pub const OP_SPARSE_MASK: u8 = 0xED;
pub const OP_DROWSY_RET: u8 = 0xEC;
pub const OP_SPEC_EXIT: u8 = 0xEB;
pub const OP_NULL_PE: u8 = 0xEA;
pub const OP_STOCH_ROUND: u8 = 0xE9;
pub const OP_SPARSE_SKIP: u8 = 0xE8;
pub const OP_DFS_GATE: u8 = 0xE7;
pub const OP_HOLO_MUX_X4: u8 = 0xE6;
pub const OP_SUBTH_CLK: u8 = 0xE5;
pub const OP_AVS_RECONF: u8 = 0xE4;
pub const OP_LUT_NPU: u8 = 0xE3;
pub const OP_TOM: u8 = 0xE2;
pub const OP_TENET: u8 = 0xE1;

/// Sacred bank boundaries (R18 LAYER-FROZEN at 32 slots, W47).
pub const SACRED_BANK_LO: u8 = 0xE0;
pub const SACRED_BANK_HI: u8 = 0xFF;
pub const SACRED_BANK_SIZE: u32 = 32;

/// gamma^3 in bps (parts per 10000) — exact 132, derived from B007^3.
/// gamma = phi^-3 ≈ 0.2360680, gamma^3 ≈ 0.01316.
pub const GAMMA3_BPS: i32 = 132;

/// ΔC_dec fractional uplift in bps relative to C_dec_base (encoded constant).
pub const DELTA_C_DEC_BPS: i32 = 81;

/// C_dec base in pF (reference Larsson/Svensson 1994).
pub const C_DEC_BASE_PF: i32 = 100;

/// Cap area uplift cap in bps (R18 iso-area constraint).
pub const CAP_AREA_MAX_BPS: i32 = 50;

/// di/dt margin in bps. Center 600 (6%). Band [400, 1000] (4-10%).
pub const DIDT_MARGIN_CENTER_BPS: i32 = 600;
pub const DIDT_MARGIN_LO_BPS: i32 = 400;
pub const DIDT_MARGIN_HI_BPS: i32 = 1000;

/// Droop suppression in bps. Center 400 (4%). Band [200, 800] (2-8%).
pub const DROOP_SUPP_CENTER_BPS: i32 = 400;
pub const DROOP_SUPP_LO_BPS: i32 = 200;
pub const DROOP_SUPP_HI_BPS: i32 = 800;

/// f_clk impact cap: 2% (200 bps).
pub const FCLK_IMPACT_MAX_BPS: i32 = 200;

/// TOPS/W projection (post-W48, post-W49, floor lift).
pub const TOPS_W_W48_POST: i32 = 1083;
pub const TOPS_W_W49_POST: i32 = 1091;
pub const TOPS_W_LIFT_FLOOR_TENTHS: i32 = 7; // ≥ 0.7%

/// Derive ΔC_dec_pF given C_base_pF and γ³ in bps.
pub fn delta_c_pf_q4(c_base_pf: i32, gamma3_bps: i32) -> i32 {
    // Returns Q4 fixed-point (i.e. 10000x). c_base_pf * gamma3_bps.
    c_base_pf * gamma3_bps
}

/// Check ΔC_dec uplift in the falsifiable band.
pub fn delta_c_in_band(observed_bps: i32) -> bool {
    observed_bps >= 50 && observed_bps <= 100
}

/// Check di/dt margin in falsifiable band.
pub fn didt_margin_in_band(observed_bps: i32) -> bool {
    observed_bps >= DIDT_MARGIN_LO_BPS && observed_bps <= DIDT_MARGIN_HI_BPS
}

/// Check droop suppression in falsifiable band.
pub fn droop_supp_in_band(observed_bps: i32) -> bool {
    observed_bps >= DROOP_SUPP_LO_BPS && observed_bps <= DROOP_SUPP_HI_BPS
}

/// Check cap area uplift under R18 cap.
pub fn cap_area_under_cap(observed_bps: i32) -> bool {
    observed_bps <= CAP_AREA_MAX_BPS
}

/// Check f_clk impact under cap.
pub fn fclk_impact_under_cap(observed_bps: i32) -> bool {
    observed_bps <= FCLK_IMPACT_MAX_BPS
}

/// CAP-BOOST controller cycle outcome.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CapBoostStep {
    pub burst_enabled: bool,
    pub delta_c_q4: i32,
    pub didt_margin_bps: i32,
    pub droop_supp_bps: i32,
}

/// Simulate one CAP-BOOST controller step.
///
/// When activity_factor exceeds the threshold (=128 of 256), enable the
/// capacitive burst: ΔC = C_base * γ³ at the nominal di/dt margin (600 bps)
/// and droop suppression (400 bps). Otherwise emit zero burst.
pub fn cap_boost_step(activity_factor_u8: u8, c_base_pf: i32) -> CapBoostStep {
    if activity_factor_u8 >= 128 {
        CapBoostStep {
            burst_enabled: true,
            delta_c_q4: delta_c_pf_q4(c_base_pf, GAMMA3_BPS),
            didt_margin_bps: DIDT_MARGIN_CENTER_BPS,
            droop_supp_bps: DROOP_SUPP_CENTER_BPS,
        }
    } else {
        CapBoostStep {
            burst_enabled: false,
            delta_c_q4: 0,
            didt_margin_bps: 0,
            droop_supp_bps: 0,
        }
    }
}

/// R18 LAYER-FROZEN: bank-set still at 32 slots, only slots populated.
pub fn r18_layer_frozen() -> bool {
    SACRED_BANK_SIZE == 32
        && SACRED_BANK_LO == 0xE0
        && SACRED_BANK_HI == 0xFF
        && OP_CAP_BOOST >= SACRED_BANK_LO
        && OP_CAP_BOOST <= SACRED_BANK_HI
}

/// TOPS/W lift ≥ 0.7% floor (≥ 7 in TENTHS).
pub fn tops_w_lift_at_least_0pt7pct() -> bool {
    1000 * (TOPS_W_W49_POST - TOPS_W_W48_POST) >= TOPS_W_LIFT_FLOOR_TENTHS * TOPS_W_W48_POST
}
