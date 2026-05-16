// SPDX-License-Identifier: Apache-2.0
// k3_alu_tb.v — Testbench for k3_alu (CLARA Gap-2, Kleene K3 ALU)
//
// 27 test cases:
//   9 AND combos + 9 OR combos + 3 NOT combos + 6 extra NOT (b ignored) = 27
// All expected PASS. Pure Verilog-2005.
`default_nettype none
`timescale 1ns/1ps

module k3_alu_tb;
    // Encoding
    localparam T_FALSE   = 2'b10;
    localparam T_UNKNOWN = 2'b00;
    localparam T_TRUE    = 2'b01;

    localparam OP_NOT = 2'b00;
    localparam OP_AND = 2'b01;
    localparam OP_OR  = 2'b10;
    localparam OP_RSV = 2'b11;

    reg  [1:0] a;
    reg  [1:0] b;
    reg  [1:0] op;
    wire [1:0] result;
    wire       valid;

    integer pass_count;
    integer fail_count;
    integer total;

    k3_alu dut (
        .a(a), .b(b), .op(op),
        .result(result), .valid(valid)
    );

    task check;
        input [1:0] exp_result;
        input       exp_valid;
        input [63:0] test_id;
        begin
            #1;
            total = total + 1;
            if (result === exp_result && valid === exp_valid) begin
                pass_count = pass_count + 1;
                $display("PASS [%0d] op=%b a=%b b=%b => result=%b valid=%b",
                         test_id, op, a, b, result, valid);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL [%0d] op=%b a=%b b=%b => result=%b valid=%b  EXPECTED result=%b valid=%b",
                         test_id, op, a, b, result, valid, exp_result, exp_valid);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        total = 0;

        $display("=== K3 ALU Testbench — CLARA Gap-2 ===");

        // -------------------------------------------------------
        // NOT tests (3 primary cases — b is don't-care, use T_FALSE)
        // -------------------------------------------------------
        $display("--- NOT (9 cases: 3 trits × 3 b-values) ---");
        op = OP_NOT; b = T_FALSE;
        a = T_TRUE;    check(T_FALSE,   1'b1, 1);
        a = T_UNKNOWN; check(T_UNKNOWN, 1'b1, 2);
        a = T_FALSE;   check(T_TRUE,    1'b1, 3);

        // NOT with b=UNKNOWN (b ignored for NOT, still valid)
        op = OP_NOT; b = T_UNKNOWN;
        a = T_TRUE;    check(T_FALSE,   1'b1, 4);
        a = T_UNKNOWN; check(T_UNKNOWN, 1'b1, 5);
        a = T_FALSE;   check(T_TRUE,    1'b1, 6);

        // NOT with b=TRUE (b ignored for NOT, still valid)
        op = OP_NOT; b = T_TRUE;
        a = T_TRUE;    check(T_FALSE,   1'b1, 7);
        a = T_UNKNOWN; check(T_UNKNOWN, 1'b1, 8);
        a = T_FALSE;   check(T_TRUE,    1'b1, 9);

        // -------------------------------------------------------
        // AND tests (9 combos)
        // -------------------------------------------------------
        $display("--- AND (9 cases) ---");
        op = OP_AND;
        a = T_TRUE;    b = T_TRUE;    check(T_TRUE,    1'b1, 10);
        a = T_TRUE;    b = T_UNKNOWN; check(T_UNKNOWN, 1'b1, 11);
        a = T_TRUE;    b = T_FALSE;   check(T_FALSE,   1'b1, 12);
        a = T_UNKNOWN; b = T_TRUE;    check(T_UNKNOWN, 1'b1, 13);
        a = T_UNKNOWN; b = T_UNKNOWN; check(T_UNKNOWN, 1'b1, 14);
        a = T_UNKNOWN; b = T_FALSE;   check(T_FALSE,   1'b1, 15);
        a = T_FALSE;   b = T_TRUE;    check(T_FALSE,   1'b1, 16);
        a = T_FALSE;   b = T_UNKNOWN; check(T_FALSE,   1'b1, 17);
        a = T_FALSE;   b = T_FALSE;   check(T_FALSE,   1'b1, 18);

        // -------------------------------------------------------
        // OR tests (9 combos)
        // -------------------------------------------------------
        $display("--- OR (9 cases) ---");
        op = OP_OR;
        a = T_TRUE;    b = T_TRUE;    check(T_TRUE,    1'b1, 19);
        a = T_TRUE;    b = T_UNKNOWN; check(T_TRUE,    1'b1, 20);
        a = T_TRUE;    b = T_FALSE;   check(T_TRUE,    1'b1, 21);
        a = T_UNKNOWN; b = T_TRUE;    check(T_TRUE,    1'b1, 22);
        a = T_UNKNOWN; b = T_UNKNOWN; check(T_UNKNOWN, 1'b1, 23);
        a = T_UNKNOWN; b = T_FALSE;   check(T_UNKNOWN, 1'b1, 24);
        a = T_FALSE;   b = T_TRUE;    check(T_TRUE,    1'b1, 25);
        a = T_FALSE;   b = T_UNKNOWN; check(T_UNKNOWN, 1'b1, 26);
        a = T_FALSE;   b = T_FALSE;   check(T_FALSE,   1'b1, 27);

        // -------------------------------------------------------
        // RESERVED — valid should be 0
        // -------------------------------------------------------
        $display("--- RESERVED (1 extra sanity) ---");
        op = OP_RSV; a = T_TRUE; b = T_TRUE;
        #1;
        if (valid === 1'b0) begin
            $display("PASS [28] RSV op correctly sets valid=0");
        end else begin
            $display("FAIL [28] RSV op should set valid=0, got valid=%b", valid);
            fail_count = fail_count + 1;
        end

        $display("==============================================");
        $display("RESULTS: %0d/%0d PASS, %0d FAIL", pass_count, total, fail_count);
        if (fail_count == 0)
            $display("STATUS: ALL PASS — K3 ALU verified 27/27 cases");
        else
            $display("STATUS: FAILURES DETECTED");
        $display("==============================================");
        $finish;
    end
endmodule
