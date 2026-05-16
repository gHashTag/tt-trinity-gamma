`default_nettype none
// restraint_ctrl.v — CLARA Gap-4 Bounded-Rationality Restraint Controller
// SPDX-License-Identifier: Apache-2.0
//
// Implements hard-wired K_UNKNOWN forcing per DARPA CLARA TA1.4.
// t27 spec: gHashTag/t27/specs/ar/restraint.t27
// CROWN47 reference: §3.4 Gap 4 (CROWN47_DARPA_DRONE_ANALYSIS.md)
//
// Triggers force_unknown = 1 when ANY of:
//   (1) phi_drift > 16'd164   (0.5% in Q1.15 ≈ 163.84 → threshold 164)
//   (2) step_count > 4'd10    (bounded rationality: MAX_STEPS=10)
//   (3) receipt_ok == 0        (receipt failure / packet integrity lost)
//
// Once tripped the restraint is STICKY until rst_n (de-asserted).
// This ensures no glitch re-enables MAC after a detected violation.
//
// reason[2:0] encoding (one-hot, sticky):
//   3'b001 = phi_drift overflow
//   3'b010 = step_count overflow
//   3'b100 = receipt failure
//   Multiple bits may be set if multiple conditions triggered.
//
// R-SI-1: zero `*` operators. Pure combinational comparison only.
// Verilog-2005 only. No SystemVerilog.
// Budget: ~100 cells (3 comparators + sticky FF + reason logic).
//
// DOI 10.5281/zenodo.19227877 · Anchor: φ²+φ⁻²=3

module restraint_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    // Inputs
    input  wire [15:0] phi_drift,      // Q1.15 from phi_distance_oracle
    input  wire [3:0]  step_count,     // from trinity_master_fsm state counter
    input  wire        receipt_ok,     // from crc32_receipt (1=valid, 0=fail)
    input  wire [1:0]  current_state,  // 00=IDLE, 01=COMPUTE, 10=EMIT
    // Outputs
    output reg         force_unknown,  // 1 when restraint triggered
    output reg         halt_mac,       // 1 to gate MAC clock (mirrored)
    output reg  [2:0]  reason          // which condition(s) tripped
);

    // ------------------------------------------------------------------
    // Condition wires (purely combinational, no `*`)
    // phi_drift threshold: 0.5% in Q1.15 = 0.005 * 32768 = 163.84 → 164
    // ------------------------------------------------------------------
    localparam [15:0] PHI_DRIFT_THRESH = 16'd164;
    localparam [3:0]  STEP_MAX         = 4'd10;

    wire cond_phi_drift   = (phi_drift   > PHI_DRIFT_THRESH);
    wire cond_step_over   = (step_count  > STEP_MAX);
    wire cond_rcpt_fail   = (~receipt_ok);

    wire any_trigger = cond_phi_drift | cond_step_over | cond_rcpt_fail;

    // ------------------------------------------------------------------
    // Sticky latch: once set, stays set until rst_n goes low.
    // Separate sticky bits per reason so we preserve which fired first.
    // ------------------------------------------------------------------
    reg sticky_phi;
    reg sticky_step;
    reg sticky_rcpt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sticky_phi  <= 1'b0;
            sticky_step <= 1'b0;
            sticky_rcpt <= 1'b0;
        end else begin
            if (cond_phi_drift) sticky_phi  <= 1'b1;
            if (cond_step_over) sticky_step <= 1'b1;
            if (cond_rcpt_fail) sticky_rcpt <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Output combinational from sticky bits
    // ------------------------------------------------------------------
    always @(*) begin
        reason[0]     = sticky_phi;
        reason[1]     = sticky_step;
        reason[2]     = sticky_rcpt;
        force_unknown = sticky_phi | sticky_step | sticky_rcpt;
        halt_mac      = force_unknown;
    end

    // Silence lint: current_state is present for future state-qualified logic
    wire _unused = &{1'b0, current_state, 1'b0};

endmodule
