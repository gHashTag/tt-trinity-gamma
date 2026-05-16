// SPDX-License-Identifier: Apache-2.0
// explainability_unit.v  — DARPA CLARA TA1.2 Explanation Generation
// TRI-1-GAMMA  Gap-5  (feat/clara-gap5-explainability)
//
// 5-tuple proof-trace emitter.
// Each inference step emits one 20-bit record:
//   [19:16] step_id[3:0]
//   [15:12] premise_id_a[3:0]
//   [11: 8] premise_id_b[3:0]
//   [ 7: 4] rule_id[3:0]
//   [ 3: 0] conclusion[3:0]
//
// Buffer: 10 × 20-bit shift register (oldest = buf[9], newest = buf[0]).
// step_count [3:0] tracks how many valid entries are in the buffer.
// When a new step is pushed while step_count == MAX_STEPS (10) → overflow=1.
//
// Serial output on trace_out[1:0]: 2 bits per cycle, MSB first.
// One complete 20-bit record takes 10 cycles.  Phase is indicated by
// serial_phase[3:0] (0..9 → bits 19..2, 17..0 pairs).
//
// overflow feeds restraint_ctrl Gap-4 via the overflow port.
//
// R-SI-1: ZERO `*` operators.  No SystemVerilog.  Pure Verilog-2005.
// Cell estimate: ~180 cells (well within 0.4 % of GAMMA's ~48 000 cell budget).
// Coq anchor: proofs/clara_max_steps.v  (MAX_STEPS invariant).
//
// DOI 10.5281/zenodo.19227877   φ²+φ⁻²=3

`default_nettype none

module explainability_unit (
    input  wire        clk,
    input  wire        rst_n,

    // Write interface — push one 5-tuple per cycle when push=1
    input  wire        push,
    input  wire [3:0]  step_id,
    input  wire [3:0]  premise_id_a,
    input  wire [3:0]  premise_id_b,
    input  wire [3:0]  rule_id,
    input  wire [3:0]  conclusion,

    // Overflow flag (to restraint_ctrl Gap-4)
    output reg         overflow,

    // Serial read-back of the most-recently-pushed record
    // 2 bits per cycle, 10-cycle frame, MSB first.
    // trace_out[1]=bit_hi, trace_out[0]=bit_lo
    output wire [1:0]  trace_out,

    // Debug: current fill level and head record
    output wire [3:0]  step_count_out,
    output wire [19:0] head_record
);

    // ------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------
    parameter MAX_STEPS = 10;   // Hard limit per t27 spec

    // ------------------------------------------------------------------
    // 10 × 20-bit shift register (flat — Verilog-2005 compatible)
    // buf0 = newest, buf9 = oldest
    // ------------------------------------------------------------------
    reg [19:0] buf0;
    reg [19:0] buf1;
    reg [19:0] buf2;
    reg [19:0] buf3;
    reg [19:0] buf4;
    reg [19:0] buf5;
    reg [19:0] buf6;
    reg [19:0] buf7;
    reg [19:0] buf8;
    reg [19:0] buf9;

    // Step counter  [3:0]  — saturates at MAX_STEPS (10 = 4'hA)
    reg [3:0]  step_count;

    // ------------------------------------------------------------------
    // Compose incoming 20-bit record
    // ------------------------------------------------------------------
    wire [19:0] new_record = {step_id, premise_id_a, premise_id_b,
                              rule_id, conclusion};

    // ------------------------------------------------------------------
    // Overflow detection: overflow when push arrives AND already full
    // ------------------------------------------------------------------
    wire full = (step_count == 4'hA); // 10 in decimal

    // ------------------------------------------------------------------
    // Shift-register push and step counter logic
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf0       <= 20'd0;
            buf1       <= 20'd0;
            buf2       <= 20'd0;
            buf3       <= 20'd0;
            buf4       <= 20'd0;
            buf5       <= 20'd0;
            buf6       <= 20'd0;
            buf7       <= 20'd0;
            buf8       <= 20'd0;
            buf9       <= 20'd0;
            step_count <= 4'd0;
            overflow   <= 1'b0;
        end else begin
            if (push) begin
                if (full) begin
                    // Buffer already full → set overflow, slide oldest out
                    overflow <= 1'b1;
                    // Shift: buf0 gets the new record, rest shift down
                    buf9 <= buf8;
                    buf8 <= buf7;
                    buf7 <= buf6;
                    buf6 <= buf5;
                    buf5 <= buf4;
                    buf4 <= buf3;
                    buf3 <= buf2;
                    buf2 <= buf1;
                    buf1 <= buf0;
                    buf0 <= new_record;
                    // step_count stays at 10
                end else begin
                    // Not full yet — push and count up
                    overflow <= 1'b0;
                    buf9 <= buf8;
                    buf8 <= buf7;
                    buf7 <= buf6;
                    buf6 <= buf5;
                    buf5 <= buf4;
                    buf4 <= buf3;
                    buf3 <= buf2;
                    buf2 <= buf1;
                    buf1 <= buf0;
                    buf0 <= new_record;
                    step_count <= step_count + 4'd1;
                end
            end else begin
                // No push — preserve overflow sticky until reset
                // (restraint_ctrl reads it combinationally, sticky helps)
            end
        end
    end

    // ------------------------------------------------------------------
    // Serial 2-bit-per-cycle output of buf0 (head / newest record).
    // 10-cycle rotating phase counter.
    // ------------------------------------------------------------------
    reg [3:0] serial_phase;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            serial_phase <= 4'd0;
        end else begin
            if (serial_phase == 4'd9)
                serial_phase <= 4'd0;
            else
                serial_phase <= serial_phase + 4'd1;
        end
    end

    // Select 2-bit slice of buf0 based on serial_phase
    // phase 0 → bits[19:18], phase 1 → bits[17:16], ..., phase 9 → bits[1:0]
    reg [1:0] trace_mux;
    always @(*) begin
        case (serial_phase)
            4'd0: trace_mux = buf0[19:18];
            4'd1: trace_mux = buf0[17:16];
            4'd2: trace_mux = buf0[15:14];
            4'd3: trace_mux = buf0[13:12];
            4'd4: trace_mux = buf0[11:10];
            4'd5: trace_mux = buf0[ 9: 8];
            4'd6: trace_mux = buf0[ 7: 6];
            4'd7: trace_mux = buf0[ 5: 4];
            4'd8: trace_mux = buf0[ 3: 2];
            4'd9: trace_mux = buf0[ 1: 0];
            default: trace_mux = 2'b00;
        endcase
    end

    assign trace_out       = trace_mux;
    assign step_count_out  = step_count;
    assign head_record     = buf0;

endmodule
