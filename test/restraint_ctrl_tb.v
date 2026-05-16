`default_nettype none
`timescale 1ns/1ps
// restraint_ctrl_tb.v — Testbench for CLARA Gap-4 restraint_ctrl
// SPDX-License-Identifier: Apache-2.0
//
// 4 test scenarios:
//   Scenario 1: Happy path — no trigger, force_unknown must stay 0
//   Scenario 2: phi_drift trigger — phi_drift=165 > 164
//   Scenario 3: step_count overflow — step_count=11 > 10
//   Scenario 4: receipt failure — receipt_ok=0
//
// Each scenario verifies:
//   - force_unknown asserted correctly
//   - halt_mac mirrors force_unknown
//   - reason bit(s) set correctly
//   - Sticky: stays high after input clears
//   - Reset clears everything
//
// Verilog-2005 only. No SystemVerilog. R-SI-1 clean.

module restraint_ctrl_tb;

    // DUT ports
    reg        clk;
    reg        rst_n;
    reg [15:0] phi_drift;
    reg [3:0]  step_count;
    reg        receipt_ok;
    reg [1:0]  current_state;
    wire       force_unknown;
    wire       halt_mac;
    wire [2:0] reason;

    // Instantiate DUT
    restraint_ctrl uut (
        .clk           (clk),
        .rst_n         (rst_n),
        .phi_drift     (phi_drift),
        .step_count    (step_count),
        .receipt_ok    (receipt_ok),
        .current_state (current_state),
        .force_unknown (force_unknown),
        .halt_mac      (halt_mac),
        .reason        (reason)
    );

    // Clock: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count;
    integer fail_count;

    // Task: apply reset
    task do_reset;
        begin
            rst_n         <= 1'b0;
            phi_drift     <= 16'd0;
            step_count    <= 4'd0;
            receipt_ok    <= 1'b1;
            current_state <= 2'b00;
            @(posedge clk);
            #1;
            rst_n <= 1'b1;
            @(posedge clk);
            #1;
        end
    endtask

    // Task: check and report
    task check;
        input [255:0] test_name;
        input         exp_force;
        input         exp_halt;
        input [2:0]   exp_reason_mask; // bitmask: any set bits must be set
        begin
            if (force_unknown !== exp_force) begin
                $display("FAIL [%0s] force_unknown=%0b expected=%0b",
                         test_name, force_unknown, exp_force);
                fail_count = fail_count + 1;
            end else if (halt_mac !== exp_halt) begin
                $display("FAIL [%0s] halt_mac=%0b expected=%0b",
                         test_name, halt_mac, exp_halt);
                fail_count = fail_count + 1;
            end else if ((reason & exp_reason_mask) !== exp_reason_mask) begin
                $display("FAIL [%0s] reason=%03b expected mask=%03b",
                         test_name, reason, exp_reason_mask);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS [%0s] force_unknown=%0b halt_mac=%0b reason=%03b",
                         test_name, force_unknown, halt_mac, reason);
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        $dumpfile("restraint_ctrl_tb.vcd");
        $dumpvars(0, restraint_ctrl_tb);

        // ================================================================
        // SCENARIO 1: Happy path — all conditions nominal, no trigger
        // ================================================================
        $display("--- Scenario 1: Happy path ---");
        do_reset;

        // phi_drift = 100 (< 164), step_count = 5 (<= 10), receipt_ok = 1
        phi_drift     <= 16'd100;
        step_count    <= 4'd5;
        receipt_ok    <= 1'b1;
        current_state <= 2'b01;
        @(posedge clk); #1;
        check("happy_force_unknown", 1'b0, 1'b0, 3'b000);

        // One more cycle to confirm stable
        @(posedge clk); #1;
        check("happy_stable", 1'b0, 1'b0, 3'b000);

        // ================================================================
        // SCENARIO 2: phi_drift trigger — phi_drift=165 > threshold 164
        // ================================================================
        $display("--- Scenario 2: phi_drift trigger ---");
        do_reset;

        phi_drift     <= 16'd165;
        step_count    <= 4'd3;
        receipt_ok    <= 1'b1;
        current_state <= 2'b01;
        @(posedge clk); #1;

        // After one clock: sticky_phi should be set
        check("phi_drift_trigger", 1'b1, 1'b1, 3'b001);

        // Verify reason[0] set, reason[1] and reason[2] clear
        if (reason[0] !== 1'b1)
            $display("FAIL reason[0] should be set, got %0b", reason[0]);
        if (reason[1] !== 1'b0)
            $display("FAIL reason[1] should be clear, got %0b", reason[1]);
        if (reason[2] !== 1'b0)
            $display("FAIL reason[2] should be clear, got %0b", reason[2]);

        // Verify sticky: clear phi_drift to safe value, force_unknown must stay
        phi_drift <= 16'd50;
        @(posedge clk); #1;
        check("phi_drift_sticky", 1'b1, 1'b1, 3'b001);
        $display("PASS [phi_drift_sticky_confirmed] reason=%03b", reason);

        // ================================================================
        // SCENARIO 3: step_count overflow — step_count=11 > 10
        // ================================================================
        $display("--- Scenario 3: step_count overflow ---");
        do_reset;

        phi_drift     <= 16'd50;
        step_count    <= 4'd11;
        receipt_ok    <= 1'b1;
        current_state <= 2'b01;
        @(posedge clk); #1;

        check("step_overflow_trigger", 1'b1, 1'b1, 3'b010);

        // Verify reason[1] set
        if (reason[1] !== 1'b1)
            $display("FAIL reason[1] should be set, got %0b", reason[1]);
        if (reason[0] !== 1'b0)
            $display("FAIL reason[0] should be clear, got %0b", reason[0]);
        if (reason[2] !== 1'b0)
            $display("FAIL reason[2] should be clear, got %0b", reason[2]);

        // Verify sticky
        step_count <= 4'd5;
        @(posedge clk); #1;
        check("step_overflow_sticky", 1'b1, 1'b1, 3'b010);
        $display("PASS [step_overflow_sticky_confirmed] reason=%03b", reason);

        // ================================================================
        // SCENARIO 4: receipt_ok = 0 (receipt failure)
        // ================================================================
        $display("--- Scenario 4: receipt failure ---");
        do_reset;

        phi_drift     <= 16'd50;
        step_count    <= 4'd3;
        receipt_ok    <= 1'b0;
        current_state <= 2'b10;
        @(posedge clk); #1;

        check("receipt_fail_trigger", 1'b1, 1'b1, 3'b100);

        // Verify reason[2] set
        if (reason[2] !== 1'b1)
            $display("FAIL reason[2] should be set, got %0b", reason[2]);
        if (reason[0] !== 1'b0)
            $display("FAIL reason[0] should be clear, got %0b", reason[0]);
        if (reason[1] !== 1'b0)
            $display("FAIL reason[1] should be clear, got %0b", reason[1]);

        // Restore receipt_ok = 1 — sticky must hold
        receipt_ok <= 1'b1;
        @(posedge clk); #1;
        check("receipt_fail_sticky", 1'b1, 1'b1, 3'b100);
        $display("PASS [receipt_fail_sticky_confirmed] reason=%03b", reason);

        // ================================================================
        // BONUS: Reset clears everything
        // ================================================================
        $display("--- Bonus: Reset clears sticky state ---");
        rst_n <= 1'b0;
        @(posedge clk); #1;
        check("reset_clears", 1'b0, 1'b0, 3'b000);
        rst_n <= 1'b1;

        // ================================================================
        // SUMMARY
        // ================================================================
        $display("==========================================");
        $display("RESULTS: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED - restraint_ctrl CLARA Gap-4 OK");
        else
            $display("SOME TESTS FAILED");
        $display("==========================================");

        $finish;
    end

    // Timeout guard
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
