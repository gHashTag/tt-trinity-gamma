// SPDX-License-Identifier: Apache-2.0
// composition_kernel.v — CLARA Gap-7 Composition Kernel
// TRI-1-GAMMA  (feat/clara-gap7-composition)
//
// Supervisor that orchestrates three CLARA modules:
//   - datalog_engine_mini (PR #58, Gap-3): forward-chain inference
//   - restraint_ctrl      (PR #60, Gap-4): bounded-rationality gating
//   - explainability_unit (PR #62, Gap-5): 5-tuple proof-trace emitter
//
// Composition rules:
//   1. Each datalog inference step (converged, new iter) → push 5-tuple
//      to explainability_unit.  step_id = iter_count[3:0].
//      premise_id_a = fact_mask[3:0], premise_id_b = fact_mask[7:4],
//      rule_id = fact_mask[11:8], conclusion = fact_mask[15:12].
//   2. If explainability_unit overflow == 1 → restraint_ctrl sees
//      step_count fed at MAX_STEPS+1 (overrides), forcing force_unknown.
//   3. Composed output: {final_facts[15:0], proof_trace_serial[1:0],
//                        force_unknown_flag}
//
// Submodules NOT yet on main (pending PR #58/#60/#62 merging).
// TODO(merge-gap3): replace inline datalog_engine_mini with src/ version
// TODO(merge-gap4): replace inline restraint_ctrl with src/ version
// TODO(merge-gap5): replace inline explainability_unit with src/ version
//
// R-SI-1: ZERO `*` operators. Pure Verilog-2005. No SystemVerilog.
// Cell budget: ~150 glue cells (submodules accounted separately).
// DOI 10.5281/zenodo.19227877  φ²+φ⁻²=3  Anchor: 0x47C0

`default_nettype none

module composition_kernel (
    input  wire        clk,
    input  wire        rst_n,

    // ----------------------------------------------------------------
    // Datalog load interface (pass-through to datalog_engine_mini)
    // ----------------------------------------------------------------
    input  wire        load_clause,
    input  wire [3:0]  clause_idx,
    input  wire [3:0]  clause_head,
    input  wire [15:0] clause_body,
    input  wire        clause_valid,

    input  wire        fact_load,
    input  wire [3:0]  fact_idx,

    // Start inference run
    input  wire        start,

    // ----------------------------------------------------------------
    // Restraint auxiliary inputs
    // ----------------------------------------------------------------
    input  wire [15:0] phi_drift,    // from phi_distance_oracle
    input  wire        receipt_ok,   // from crc32_receipt

    // ----------------------------------------------------------------
    // Composed outputs
    // ----------------------------------------------------------------
    output wire [15:0] final_facts,         // datalog fact_mask
    output wire [1:0]  proof_trace_serial,  // 2-bit/cycle serial from explainability_unit
    output wire        force_unknown_flag,  // restraint trigger

    // Debug / observer
    output wire        converged_out,
    output wire [3:0]  iter_count_out,
    output wire        overflow_out,
    output wire [2:0]  restraint_reason
);

    // ================================================================
    // datalog_engine_mini wires
    // ================================================================
    wire [15:0] dl_fact_mask;
    wire        dl_converged;
    wire [3:0]  dl_iter_count;

    // ================================================================
    // explainability_unit wires
    // ================================================================
    wire        eu_overflow;
    wire [1:0]  eu_trace_out;
    wire [3:0]  eu_step_count_out;
    wire [19:0] eu_head_record;

    // ================================================================
    // restraint_ctrl wires
    // ================================================================
    wire        rc_force_unknown;
    wire        rc_halt_mac;
    wire [2:0]  rc_reason;

    // ================================================================
    // Glue: supervisor state machine
    // ================================================================
    // States: IDLE → WAIT_CONVERGE → EMIT_TRACE → DONE
    localparam SV_IDLE          = 2'b00;
    localparam SV_WAIT_CONVERGE = 2'b01;
    localparam SV_EMIT_TRACE    = 2'b10;
    localparam SV_DONE          = 2'b11;

    reg [1:0]  sv_state;
    reg        dl_start_r;      // one-cycle pulse to datalog
    reg        eu_push_r;       // one-cycle push to explainability_unit
    reg [3:0]  prev_iter;       // detect new inference step
    reg [3:0]  emit_step;       // which step we are auto-pushing

    // 5-tuple components latched from fact_mask at each new inference step
    reg [3:0]  t_step_id;
    reg [3:0]  t_premise_a;
    reg [3:0]  t_premise_b;
    reg [3:0]  t_rule_id;
    reg [3:0]  t_conclusion;

    // ================================================================
    // Overflow-driven restraint: when eu_overflow=1, we force
    // step_count input to restraint_ctrl above MAX_STEPS threshold (>10)
    // by feeding 4'd11 instead of the normal dl_iter_count.
    // ================================================================
    wire [3:0] rc_step_count_in = eu_overflow ? 4'd11 : dl_iter_count;

    // restraint_ctrl also uses phi_drift and receipt_ok from top ports.
    // current_state mirrors supervisor state low 2 bits.
    wire [1:0] rc_current_state = sv_state;

    // ================================================================
    // Supervisor FSM
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sv_state    <= SV_IDLE;
            dl_start_r  <= 1'b0;
            eu_push_r   <= 1'b0;
            prev_iter   <= 4'd0;
            emit_step   <= 4'd0;
            t_step_id   <= 4'd0;
            t_premise_a <= 4'd0;
            t_premise_b <= 4'd0;
            t_rule_id   <= 4'd0;
            t_conclusion <= 4'd0;
        end else begin
            // Default: clear one-cycle pulses
            dl_start_r <= 1'b0;
            eu_push_r  <= 1'b0;

            case (sv_state)
                SV_IDLE: begin
                    prev_iter <= 4'd0;
                    if (start) begin
                        dl_start_r <= 1'b1;
                        sv_state   <= SV_WAIT_CONVERGE;
                    end
                end

                SV_WAIT_CONVERGE: begin
                    // Detect new inference step (iter_count advanced)
                    if (dl_iter_count != prev_iter) begin
                        prev_iter    <= dl_iter_count;
                        // Latch 5-tuple from current fact_mask
                        t_step_id    <= dl_iter_count;
                        t_premise_a  <= dl_fact_mask[3:0];
                        t_premise_b  <= dl_fact_mask[7:4];
                        t_rule_id    <= dl_fact_mask[11:8];
                        t_conclusion <= dl_fact_mask[15:12];
                        // Push to explainability_unit next cycle
                        eu_push_r    <= 1'b1;
                    end

                    if (dl_converged) begin
                        sv_state <= SV_EMIT_TRACE;
                    end
                end

                SV_EMIT_TRACE: begin
                    // Wait 10 cycles for serial trace to flush (10-cycle frame)
                    // We use emit_step as a down-counter (0..9)
                    if (emit_step == 4'd9) begin
                        emit_step <= 4'd0;
                        sv_state  <= SV_DONE;
                    end else begin
                        emit_step <= emit_step + 4'd1;
                    end
                end

                SV_DONE: begin
                    // Latch: stay done. Accept new start.
                    if (start) begin
                        dl_start_r <= 1'b1;
                        prev_iter  <= 4'd0;
                        emit_step  <= 4'd0;
                        sv_state   <= SV_WAIT_CONVERGE;
                    end
                end

                default: sv_state <= SV_IDLE;
            endcase
        end
    end

    // ================================================================
    // Submodule instantiations
    // TODO(merge-gap3): once PR #58 merged to main, these inline copies
    //                   become unreachable and can be removed (src/ wins).
    // ================================================================

    // --- Gap-3: datalog_engine_mini ---
    datalog_engine_mini u_datalog (
        .clk          (clk),
        .rst_n        (rst_n),
        .load_clause  (load_clause),
        .clause_idx   (clause_idx),
        .clause_head  (clause_head),
        .clause_body  (clause_body),
        .clause_valid (clause_valid),
        .fact_load    (fact_load),
        .fact_idx     (fact_idx),
        .start        (dl_start_r),
        .fact_mask    (dl_fact_mask),
        .converged    (dl_converged),
        .iter_count   (dl_iter_count)
    );

    // --- Gap-5: explainability_unit ---
    // TODO(merge-gap5): once PR #62 merged to main, inline copy removed.
    explainability_unit u_explain (
        .clk           (clk),
        .rst_n         (rst_n),
        .push          (eu_push_r),
        .step_id       (t_step_id),
        .premise_id_a  (t_premise_a),
        .premise_id_b  (t_premise_b),
        .rule_id       (t_rule_id),
        .conclusion    (t_conclusion),
        .overflow      (eu_overflow),
        .trace_out     (eu_trace_out),
        .step_count_out(eu_step_count_out),
        .head_record   (eu_head_record)
    );

    // --- Gap-4: restraint_ctrl ---
    // TODO(merge-gap4): once PR #60 merged to main, inline copy removed.
    restraint_ctrl u_restraint (
        .clk           (clk),
        .rst_n         (rst_n),
        .phi_drift     (phi_drift),
        .step_count    (rc_step_count_in),
        .receipt_ok    (receipt_ok),
        .current_state (rc_current_state),
        .force_unknown (rc_force_unknown),
        .halt_mac      (rc_halt_mac),
        .reason        (rc_reason)
    );

    // ================================================================
    // Output assignments
    // ================================================================
    assign final_facts        = dl_fact_mask;
    assign proof_trace_serial = eu_trace_out;
    assign force_unknown_flag = rc_force_unknown;

    assign converged_out  = dl_converged;
    assign iter_count_out = dl_iter_count;
    assign overflow_out   = eu_overflow;
    assign restraint_reason = rc_reason;

    // Silence lint — eu debug outputs not used externally
    wire _unused = &{1'b0, eu_step_count_out, eu_head_record,
                     rc_halt_mac, 1'b0};

endmodule
