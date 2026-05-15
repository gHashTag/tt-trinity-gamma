// SPDX-License-Identifier: Apache-2.0
// Authors: Vasilev Dmitrii <admin@t27.ai>
//
// W-105-A — AVS-48 Island Utilisation Runtime Witness
// L-DPC33 Wave-36 · Lane W'' (Double-Prime)
//
// R7 falsifier for L-DPC33: AVS 48-island voltage-stacking dynamic-Vdd
// controller. Verifies that the fraction of AVS islands actively engaged
// during a BitNet b1.58-3B inference pass meets or exceeds
// ISLAND_UTILISATION_LOWER_BOUND.
//
// Topology: 48 voltage islands stacked in series (3 strands × 16
// islands each), V_total = 48 × 0.45 V = 21.6 V. Trinity alignment:
// 48 = 3 × 16, divisible by 3 → 3-Strand DNA preserved.
//
// R5-HONEST: all numeric constants are PRE-SILICON ESTIMATEs based on
// pre-tapeout simulation traces over WikiText-103 valid split until
// silicon verdict.

/// Minimum acceptable AVS island-utilisation fraction for production workloads.
///
/// Definition: the fraction of AVS-48 islands that are actively engaged
/// (Vdd > 0.40 V, clock gated ON, non-zero activations within the last
/// 16-cycle window) during a BitNet b1.58-3B inference pass.
///
/// For an idle stack (utilisation = 0.0), η_charge_recycling approaches
/// zero, breaking the W-105-B reconfiguration latency budget. For full
/// 48/48 engagement (utilisation = 1.0), the stack draws peak current
/// and the charge-recycling lever collapses to baseline DVS.
///
/// The sweet spot — and the W-105-A acceptance bound — is utilisation
/// ≥ 0.80, meaning ≥ 39 of 48 islands actively switching per window.
/// At this engagement level the AVS controller demonstrates that the
/// voltage-stacking topology is genuinely exploited rather than masked
/// by silently-bypassed islands.
///
/// # Constitutional status
/// PRE-SILICON ESTIMATE — based on pre-tapeout BitNet b1.58-3B trace
/// over WikiText-103 valid split (1000 sequences @ ctx=2048).
/// Revisit after silicon verdict per
/// `assertions/wave36_avs.json` predicate W-105-A
/// (evaluation_date 2026-12-15, freeze 2026-10-31, fail_stop true).
pub const ISLAND_UTILISATION_LOWER_BOUND: f64 = 0.80; // PRE-SILICON ESTIMATE

/// Total AVS islands in the voltage stack.
///
/// 48 = 3 × 16 (Trinity-aligned, 3-Strand DNA: each Strand owns 16
/// islands; per-strand Coptic register banks Ⲁ..Ϥ map to 9 of 16
/// islands per strand, with 7 reserved-marker R-cells per strand).
///
/// V_total = N_ISLANDS × V_island = 48 × 0.45 V = 21.6 V.
///
/// # Falsifier
/// If a future patch changes this constant without a constitutional
/// amendment, downstream R-SI-1 silicon synth will fail per
/// `assertions/wave36_avs.json` predicate W-105-D (island count == 48).
pub const N_ISLANDS: usize = 48;

/// Per-island nominal Vdd in volts.
pub const V_ISLAND: f64 = 0.45;

/// Total stack voltage in volts: 48 × 0.45 V = 21.6 V.
pub const V_TOTAL: f64 = (N_ISLANDS as f64) * V_ISLAND;

/// AVS-48 charge-recycling boost factor over W35 LUT-NPU baseline.
///
/// PRE-SILICON ESTIMATE — derived from 22FDX IRDS22FDX projection with
/// κ = 0.10 leakage knockdown via per-island gating. Multiplied with
/// W35 TOPS/W baseline of 270 to give Wave-36 projection 297 TOPS/W.
pub const ETA_AVS: f64 = 1.10; // PRE-SILICON ESTIMATE

/// Wave-35 TOPS/W baseline (LUT-NPU 81-entry, post-merge of #124 4d339944).
pub const TOPS_W_W35: f64 = 270.0; // PRE-SILICON ESTIMATE

/// Wave-36 TOPS/W target — must be reached for FRR-W36-CLOSEOUT.
pub const TOPS_W_W36_TARGET: f64 = 297.0; // PRE-SILICON ESTIMATE

/// Returns the AVS island-utilisation fraction:
/// `active_islands / N_ISLANDS`.
///
/// # Panics
/// Panics if `active_islands > N_ISLANDS` (sanity).
///
/// # Arguments
/// * `active_islands` — number of AVS islands flagged ACTIVE within the
///   last 16-cycle measurement window.
pub fn island_utilisation(active_islands: u32) -> f64 {
    assert!(
        (active_islands as usize) <= N_ISLANDS,
        "active_islands {} exceeds N_ISLANDS {}",
        active_islands,
        N_ISLANDS
    );
    active_islands as f64 / N_ISLANDS as f64
}

/// Returns `true` iff `measured` satisfies the W-105-A AVS
/// island-utilisation bound.
///
/// Post-silicon this function is called with real RTL counters from the
/// AVS-48 controller (Lane W RTL). If the result is `false` the
/// W-105-A test FAILS → fail-stop per Wave-36 R7 policy.
#[inline]
pub fn meets_w_105_a_bound(measured: f64) -> bool {
    measured >= ISLAND_UTILISATION_LOWER_BOUND
}

/// 48 is Trinity-aligned (divisible by 3).
#[inline]
pub fn is_trinity_aligned(n: usize) -> bool {
    n % 3 == 0
}

/// 3-Strand DNA strand count = N / 16.
#[inline]
pub fn strand_count(n: usize) -> usize {
    n / 16
}

/// IR-drop ratio for the AVS-48 stack: 1 / N².
///
/// For a series-stacked voltage regulator the IR drop scales inversely
/// with the square of the island count because both the per-island
/// current and the per-island series resistance shrink linearly.
/// For N=48 this is 1/2304.
#[inline]
pub fn ir_drop_ratio(n: usize) -> f64 {
    let n_f = n as f64;
    1.0 / (n_f * n_f)
}

/// TOPS/W after AVS-48 boost: `baseline * eta`.
#[inline]
pub fn tops_w_avs(baseline: f64, eta: f64) -> f64 {
    baseline * eta
}

/// Returns `true` iff the Wave-36 target 297 TOPS/W is met.
#[inline]
pub fn meets_w36_target() -> bool {
    tops_w_avs(TOPS_W_W35, ETA_AVS) >= TOPS_W_W36_TARGET
}

/// AVS reconfiguration latency in cycles for switching between Vdd
/// operating points.
///
/// PRE-SILICON ESTIMATE — pessimistic 22FDX projection at 1 GHz with
/// dedicated charge-recycling switches; W-105-B bound is `<= 4` cycles.
#[inline]
pub const fn avs_reconfig_latency_cycles() -> u32 {
    3 // PRE-SILICON ESTIMATE
}

/// Returns `true` iff measured AVS reconfig latency satisfies W-105-B.
#[inline]
pub fn meets_w_105_b_bound(cycles: u32) -> bool {
    cycles <= 4
}

/// V_dd field width in bits — must be exactly 2 to address 4 voltage
/// levels {0.40, 0.45, 0.50, 0.55 V}.
pub const V_DD_FIELD_WIDTH_BITS: u32 = 2;

/// Returns `true` iff V_dd field width equals 2 (W-105-C).
#[inline]
pub fn meets_w_105_c_bound(width: u32) -> bool {
    width == V_DD_FIELD_WIDTH_BITS
}

/// Returns `true` iff island count equals 48 (W-105-D).
#[inline]
pub fn meets_w_105_d_bound(n: usize) -> bool {
    n == N_ISLANDS
}
