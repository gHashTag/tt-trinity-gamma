// SPDX-License-Identifier: Apache-2.0
// datalog_engine_mini_tb.v — Testbench for CLARA Gap-3 datalog engine
// 3-rule chain example:
//   Rule 0 (idx=0): A0 ← (unconditional fact)  head=0, body=FFFF
//   Rule 1 (idx=1): A1 ← A0                    head=1, body=F_F_F_0 = {4'hF,4'hF,4'hF,4'h0}
//   Rule 2 (idx=2): A2 ← A0 AND A1             head=2, body=F_F_1_0 = {4'hF,4'hF,4'h1,4'h0}
//
// Expected convergence: ≤3 iterations
//   Pass 0→1: Rule 0 fires (all body=0xF satisfied) → A0 set
//   Pass 1→2: Rule 1 fires (A0 set) → A1 set
//   Pass 2→3: Rule 2 fires (A0,A1 set) → A2 set; Rule 0,1 still fire → no change to existing
//   Pass 3→4: No new facts → converged
//
// We also verify that fact_mask[0], fact_mask[1], fact_mask[2] are all set.

`default_nettype none
`timescale 1ns/1ps

module datalog_engine_mini_tb;

    // DUT signals
    reg         clk;
    reg         rst_n;
    reg         load_clause;
    reg  [3:0]  clause_idx;
    reg  [3:0]  clause_head;
    reg  [15:0] clause_body;
    reg         clause_valid;
    reg         fact_load;
    reg  [3:0]  fact_idx;
    reg         start;

    wire [15:0] fact_mask;
    wire        converged;
    wire [3:0]  iter_count;

    // Instantiate DUT
    datalog_engine_mini dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .load_clause  (load_clause),
        .clause_idx   (clause_idx),
        .clause_head  (clause_head),
        .clause_body  (clause_body),
        .clause_valid (clause_valid),
        .fact_load    (fact_load),
        .fact_idx     (fact_idx),
        .start        (start),
        .fact_mask    (fact_mask),
        .converged    (converged),
        .iter_count   (iter_count)
    );

    // 10 ns clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Test results
    integer errors;
    integer pass;

    // Task: load a single clause
    task load_one_clause;
        input [3:0]  idx;
        input [3:0]  head;
        input [15:0] body;
        input        valid;
        begin
            @(negedge clk);
            load_clause  <= 1'b1;
            clause_idx   <= idx;
            clause_head  <= head;
            clause_body  <= body;
            clause_valid <= valid;
            @(negedge clk);
            load_clause  <= 1'b0;
        end
    endtask

    integer timeout;

    initial begin
        errors     = 0;
        pass       = 0;
        load_clause = 0;
        clause_idx  = 0;
        clause_head = 0;
        clause_body = 0;
        clause_valid = 0;
        fact_load   = 0;
        fact_idx    = 0;
        start       = 0;

        // Reset
        rst_n = 0;
        repeat(4) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        $display("=== CLARA Gap-3 datalog_engine_mini testbench ===");
        $display("  Rule 0: A0 <- (fact/unconditional)");
        $display("  Rule 1: A1 <- A0");
        $display("  Rule 2: A2 <- A0 AND A1");

        // -----------------------------------------------------------
        // Load 3 clauses
        // Rule 0: head=0, body=all-0xF (unconditional fact)
        //   body packed: {body3=F, body2=F, body1=F, body0=F} = 16'hFFFF
        // Rule 1: head=1, body: b0=0 (A0), rest=F
        //   body packed: {body3=F, body2=F, body1=F, body0=0} = {4'hF,4'hF,4'hF,4'h0} = 16'hFFF0
        // Rule 2: head=2, body: b0=0 (A0), b1=1 (A1), rest=F
        //   body packed: {body3=F, body2=F, body1=1, body0=0} = {4'hF,4'hF,4'h1,4'h0} = 16'hFF10
        // -----------------------------------------------------------
        load_one_clause(4'd0, 4'd0, 16'hFFFF, 1'b1); // A0 <- (fact)
        load_one_clause(4'd1, 4'd1, 16'hFFF0, 1'b1); // A1 <- A0
        load_one_clause(4'd2, 4'd2, 16'hFF10, 1'b1); // A2 <- A0 & A1

        $display("[TB] Clauses loaded.");

        // -----------------------------------------------------------
        // Start forward chaining
        // -----------------------------------------------------------
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        // -----------------------------------------------------------
        // Wait for convergence (timeout after 20 clocks)
        // -----------------------------------------------------------
        timeout = 0;
        while (!converged && timeout < 20) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end

        // -----------------------------------------------------------
        // Check results
        // -----------------------------------------------------------
        $display("[TB] converged=%b iter_count=%0d fact_mask=0x%04h",
                 converged, iter_count, fact_mask);

        // Check 1: converged must be asserted
        if (!converged) begin
            $display("FAIL: not converged within timeout");
            errors = errors + 1;
        end else begin
            $display("PASS: converged asserted");
            pass = pass + 1;
        end

        // Check 2: iter_count <= 4 (≤4 passes for 3-rule chain)
        if (iter_count > 4'd4) begin
            $display("FAIL: iter_count=%0d > 4", iter_count);
            errors = errors + 1;
        end else begin
            $display("PASS: iter_count=%0d <= 4 (spec: <=3 iter convergence)", iter_count);
            pass = pass + 1;
        end

        // Check 3: A0 (bit 0) is set
        if (!fact_mask[0]) begin
            $display("FAIL: A0 (bit 0) not set in fact_mask");
            errors = errors + 1;
        end else begin
            $display("PASS: A0 (bit 0) set");
            pass = pass + 1;
        end

        // Check 4: A1 (bit 1) is set
        if (!fact_mask[1]) begin
            $display("FAIL: A1 (bit 1) not set in fact_mask");
            errors = errors + 1;
        end else begin
            $display("PASS: A1 (bit 1) set");
            pass = pass + 1;
        end

        // Check 5: A2 (bit 2) is set
        if (!fact_mask[2]) begin
            $display("FAIL: A2 (bit 2) not set in fact_mask");
            errors = errors + 1;
        end else begin
            $display("PASS: A2 (bit 2) set");
            pass = pass + 1;
        end

        // Check 6: bits 3..15 are NOT set (no spurious derivations)
        if (fact_mask[15:3] != 13'h0) begin
            $display("FAIL: spurious facts in fact_mask[15:3] = %b", fact_mask[15:3]);
            errors = errors + 1;
        end else begin
            $display("PASS: no spurious facts in upper bits");
            pass = pass + 1;
        end

        // -----------------------------------------------------------
        // Summary
        // -----------------------------------------------------------
        $display("=== RESULT: %0d passed, %0d failed ===", pass, errors);
        if (errors == 0)
            $display("ALL TESTS PASSED — iter_count=%0d converged=%b fact_mask=0x%04h",
                     iter_count, converged, fact_mask);
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

    // Safety watchdog
    initial begin
        #10000;
        $display("WATCHDOG: simulation timed out");
        $finish;
    end

endmodule
`default_nettype wire
