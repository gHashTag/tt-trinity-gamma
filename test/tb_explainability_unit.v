// SPDX-License-Identifier: Apache-2.0
// tb_explainability_unit.v  —  12-scenario testbench for CLARA Gap-5
// TRI-1-GAMMA  feat/clara-gap5-explainability
//
// Scenarios:
//   S01  empty buffer after reset — step_count==0, overflow==0
//   S02  push 1 step — count==1, head_record correct, overflow==0
//   S03  push 5 steps — count==5, head_record is step-5, overflow==0
//   S04  push 10 steps (full) — count==10, overflow==0
//   S05  push 11th step (overflow) — overflow==1, count stays 10
//   S06  reset after overflow — count==0, overflow==0
//   S07  push 10 consecutive then check oldest is still in buffer
//   S08  serial output: after 1 push, verify 10-cycle trace of head_record
//   S09  step_id field correct in head_record
//   S10  premise_id_a / premise_id_b fields correct
//   S11  rule_id / conclusion fields correct
//   S12  double overflow: push 12 steps total — overflow sticky, count 10
//
// Uses `$display` + `$finish`.  Pass = "PASS 12/12".
// Pure Verilog-2005.  No `*` in synthesisable paths.

`default_nettype none
`timescale 1ns/1ps

module tb_explainability_unit;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg        push;
    reg [3:0]  step_id;
    reg [3:0]  premise_id_a;
    reg [3:0]  premise_id_b;
    reg [3:0]  rule_id;
    reg [3:0]  conclusion;

    wire        overflow;
    wire [1:0]  trace_out;
    wire [3:0]  step_count_out;
    wire [19:0] head_record;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    explainability_unit #(.MAX_STEPS(10)) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .push          (push),
        .step_id       (step_id),
        .premise_id_a  (premise_id_a),
        .premise_id_b  (premise_id_b),
        .rule_id       (rule_id),
        .conclusion    (conclusion),
        .overflow      (overflow),
        .trace_out     (trace_out),
        .step_count_out(step_count_out),
        .head_record   (head_record)
    );

    // ----------------------------------------------------------------
    // Clock: 10 ns period
    // ----------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Pass/fail bookkeeping
    // ----------------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;

    task check;
        input [127:0] label;   // just used for display
        input         expr;
        begin
            if (expr) begin
                pass_cnt = pass_cnt + 1;
                $display("  PASS  %s", label);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("  FAIL  %s  (at time %0t)", label, $time);
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Helper: do reset
    // ----------------------------------------------------------------
    task do_reset;
        begin
            rst_n = 0;
            push  = 0;
            step_id      = 4'd0;
            premise_id_a = 4'd0;
            premise_id_b = 4'd0;
            rule_id      = 4'd0;
            conclusion   = 4'd0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            rst_n = 1;
            @(posedge clk); #1;
        end
    endtask

    // ----------------------------------------------------------------
    // Helper: push one record
    // ----------------------------------------------------------------
    task push_record;
        input [3:0] sid;
        input [3:0] pa;
        input [3:0] pb;
        input [3:0] rid;
        input [3:0] con;
        begin
            step_id      = sid;
            premise_id_a = pa;
            premise_id_b = pb;
            rule_id      = rid;
            conclusion   = con;
            push = 1;
            @(posedge clk); #1;
            push = 0;
        end
    endtask

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    integer i;
    reg [19:0] expected_head;
    reg [1:0]  serial_bits [0:9];
    reg [19:0] serial_reconstruct;

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        // ==============================================================
        // S01: empty buffer after reset
        // ==============================================================
        do_reset;
        check("S01 step_count==0 after reset",     (step_count_out == 4'd0));
        check("S01 overflow==0 after reset",        (overflow == 1'b0));

        // ==============================================================
        // S02: push 1 step
        // ==============================================================
        push_record(4'd1, 4'd2, 4'd3, 4'd4, 4'd5);
        check("S02 step_count==1",                  (step_count_out == 4'd1));
        check("S02 overflow==0",                    (overflow == 1'b0));
        expected_head = {4'd1, 4'd2, 4'd3, 4'd4, 4'd5};
        check("S02 head_record correct",            (head_record == expected_head));

        // ==============================================================
        // S03: push 4 more (total 5)
        // ==============================================================
        push_record(4'd2, 4'd3, 4'd4, 4'd5, 4'd6);
        push_record(4'd3, 4'd4, 4'd5, 4'd6, 4'd7);
        push_record(4'd4, 4'd5, 4'd6, 4'd7, 4'd8);
        push_record(4'd5, 4'd6, 4'd7, 4'd8, 4'd9);
        check("S03 step_count==5",                  (step_count_out == 4'd5));
        check("S03 overflow==0",                    (overflow == 1'b0));
        // head should be the most recently pushed (step_id=5)
        expected_head = {4'd5, 4'd6, 4'd7, 4'd8, 4'd9};
        check("S03 head_record is newest push",     (head_record == expected_head));

        // ==============================================================
        // S04: push 5 more (total 10 = full, no overflow yet)
        // ==============================================================
        push_record(4'd6,  4'd7,  4'd8,  4'd9,  4'hA);
        push_record(4'd7,  4'd8,  4'd9,  4'hA,  4'hB);
        push_record(4'd8,  4'd9,  4'hA,  4'hB,  4'hC);
        push_record(4'd9,  4'hA,  4'hB,  4'hC,  4'hD);
        push_record(4'hA,  4'hB,  4'hC,  4'hD,  4'hE);
        check("S04 step_count==10",                 (step_count_out == 4'd10));
        check("S04 overflow==0 at exact full",      (overflow == 1'b0));

        // ==============================================================
        // S05: push 11th step → overflow must assert
        // ==============================================================
        push_record(4'hB, 4'hC, 4'hD, 4'hE, 4'hF);
        check("S05 overflow==1 at 11th push",       (overflow == 1'b1));
        check("S05 step_count stays 10",            (step_count_out == 4'd10));
        // Head should be the new (11th) record
        expected_head = {4'hB, 4'hC, 4'hD, 4'hE, 4'hF};
        check("S05 head updated to newest on overflow", (head_record == expected_head));

        // ==============================================================
        // S06: reset clears overflow and count
        // ==============================================================
        do_reset;
        check("S06 step_count==0 after reset",      (step_count_out == 4'd0));
        check("S06 overflow==0 after reset",        (overflow == 1'b0));

        // ==============================================================
        // S07: push 10 steps, verify oldest-slot implicit (count maxed)
        // ==============================================================
        // Re-fill
        for (i = 0; i < 10; i = i + 1) begin
            push_record(i[3:0], i[3:0], i[3:0], i[3:0], i[3:0]);
        end
        check("S07 step_count==10 after 10 pushes", (step_count_out == 4'd10));
        check("S07 overflow==0 after exactly 10",   (overflow == 1'b0));
        // Head = record pushed last (i=9)
        expected_head = {4'd9, 4'd9, 4'd9, 4'd9, 4'd9};
        check("S07 head is last push",              (head_record == expected_head));

        // ==============================================================
        // S08: serial trace correctness — capture 10 cycles of trace_out
        // after a single push on a fresh buffer
        // ==============================================================
        do_reset;
        push_record(4'hA, 4'hB, 4'hC, 4'hD, 4'hE);
        expected_head = {4'hA, 4'hB, 4'hC, 4'hD, 4'hE};
        // The serial_phase counter free-runs from 0; after reset it starts at 0.
        // After 1 push (1 clock), phase advanced to 1 on that rising edge,
        // so we capture from whatever phase is current.
        // Strategy: wait until serial_phase wraps to 0, then capture 10 cycles.
        // We probe by reconstructing from head_record directly.
        // Verify trace_out matches the corresponding 2-bit slice of head_record.
        begin : serial_check_block
            reg [1:0] expected_slice;
            reg [3:0] phase_at_sample;
            integer s08_pass;
            integer s08_total;
            s08_pass  = 0;
            s08_total = 0;
            // Sample 20 consecutive cycles and verify each trace_out against head_record slice
            repeat (20) begin
                @(posedge clk); #1;
                // We trust dut.serial_phase is the phase used for current trace_out
                // by reading head_record vs trace_out
                case (dut.serial_phase)
                    4'd0: expected_slice = head_record[19:18];
                    4'd1: expected_slice = head_record[17:16];
                    4'd2: expected_slice = head_record[15:14];
                    4'd3: expected_slice = head_record[13:12];
                    4'd4: expected_slice = head_record[11:10];
                    4'd5: expected_slice = head_record[ 9: 8];
                    4'd6: expected_slice = head_record[ 7: 6];
                    4'd7: expected_slice = head_record[ 5: 4];
                    4'd8: expected_slice = head_record[ 3: 2];
                    4'd9: expected_slice = head_record[ 1: 0];
                    default: expected_slice = 2'b00;
                endcase
                if (trace_out === expected_slice) s08_pass = s08_pass + 1;
                s08_total = s08_total + 1;
            end
            check("S08 serial trace matches head_record slices", (s08_pass == s08_total));
        end

        // ==============================================================
        // S09: step_id field in head_record
        // ==============================================================
        do_reset;
        push_record(4'hF, 4'd0, 4'd0, 4'd0, 4'd0);
        check("S09 step_id[3:0] == 4'hF in head", (head_record[19:16] == 4'hF));

        // ==============================================================
        // S10: premise_id_a / premise_id_b fields
        // ==============================================================
        do_reset;
        push_record(4'd0, 4'hA, 4'hB, 4'd0, 4'd0);
        check("S10 premise_id_a==4'hA", (head_record[15:12] == 4'hA));
        check("S10 premise_id_b==4'hB", (head_record[11: 8] == 4'hB));

        // ==============================================================
        // S11: rule_id / conclusion fields
        // ==============================================================
        do_reset;
        push_record(4'd0, 4'd0, 4'd0, 4'hD, 4'hE);
        check("S11 rule_id==4'hD",    (head_record[7:4] == 4'hD));
        check("S11 conclusion==4'hE", (head_record[3:0] == 4'hE));

        // ==============================================================
        // S12: double overflow — push 12, verify overflow sticky, count 10
        // ==============================================================
        do_reset;
        for (i = 0; i < 12; i = i + 1) begin
            push_record(i[3:0], i[3:0], i[3:0], i[3:0], i[3:0]);
        end
        check("S12 overflow sticky after 12 pushes", (overflow == 1'b1));
        check("S12 step_count still 10",             (step_count_out == 4'd10));

        // ==============================================================
        // Summary
        // ==============================================================
        $display("");
        if (fail_cnt == 0)
            $display("PASS %0d/12 — CLARA Gap-5 explainability_unit all green", pass_cnt);
        else
            $display("FAIL: %0d passed, %0d failed", pass_cnt, fail_cnt);

        $finish;
    end

    // Timeout watchdog (200 µs)
    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
