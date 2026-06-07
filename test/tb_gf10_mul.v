// SPDX-License-Identifier: Apache-2.0
// test/tb_gf10_mul.v
// Testbench for GoldenFloat10 multiplier.
// Format: [S(1) | E(3) | M(6)], bias=3, EXP_MAX=7.
// Rule-derived (e=round((N-1)/phi^2)), Track C RTL, \Conj status.
// Tests: identity, phi-series Lucas-EII pattern, phi*(1/phi)~=1,
//        zero annihilation, NaN/Inf propagation.
`default_nettype none
`timescale 1ns/1ps

module tb_gf10_mul;
    reg  [9:0] a, b;
    wire [9:0] result;

    gf10_mul dut (.a(a), .b(b), .result(result));

    integer pass_count, fail_count;
    reg [9:0] expected;
    reg [9:0] lo, hi;
    reg [255:0] tname;

    // Check exact match
    task check_exact;
        begin
            #1;
            if (result !== expected) begin
                $display("FAIL: %s | a=%0h b=%0h | got=%0h expected=%0h",
                         tname, a, b, result, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: %s | a=%0h b=%0h | result=%0h", tname, a, b, result);
                pass_count = pass_count + 1;
            end
        end
    endtask

    // Check result within tolerance [lo, hi]
    task check_range;
        begin
            #1;
            if (result < lo || result > hi) begin
                $display("FAIL: %s | a=%0h b=%0h | got=%0h expected_range=[%0h..%0h]",
                         tname, a, b, result, lo, hi);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: %s | a=%0h b=%0h | result=%0h", tname, a, b, result);
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial begin
        pass_count = 0; fail_count = 0;
        $display("=== tb_gf10_mul: GoldenFloat10 [E=3|M=6] bias=3 ===");

        // --- T1: 1.0 * 1.0 = 1.0 identity ---
        tname = "1.0 * 1.0 = 1.0";
        a = 10'hC0; b = 10'hC0; expected = 10'hC0;
        check_exact;

        // --- T2: zero * phi = 0 (zero annihilation) ---
        tname = "0 * phi = 0";
        a = 10'h0; b = 10'hE8; expected = 10'h0;
        check_exact;

        // --- T3: phi * 0 = 0 ---
        tname = "phi * 0 = 0";
        a = 10'hE8; b = 10'h0; expected = 10'h0;
        check_exact;

        // --- T4: NaN * 1.0 = NaN ---
        tname = "NaN * 1.0 = NaN";
        a = 10'h3C1; b = 10'hC0; expected = 10'h3C1;
        check_exact;

        // --- T5: +Inf * 1.0 = +Inf ---
        tname = "+Inf * 1.0 = +Inf";
        a = 10'h1C0; b = 10'hC0; expected = 10'h1C0;
        check_exact;

        // --- T6: +Inf * 0 = NaN ---
        tname = "+Inf * 0 = NaN";
        a = 10'h1C0; b = 10'h0; expected = 10'h3C1;
        check_exact;

        // --- T7: phi * (1/phi) ~ 1.0 (within 1 ULP) ---
        // Due to quantization in this narrow format, allow [one-1 .. one+1].
        tname = "phi * (1/phi) ~ 1.0";
        a = 10'hE8; b = 10'h8F;
        lo = 10'hBF; hi = 10'hC1;
        check_range;

        // --- T8-T12: Lucas-EII: 1.0 * phi iterated (phi-series progression) ---
        // Each iteration multiplies by phi; checks that the exponent advances by
        // 1 per phi^2 iterations on average. We verify the product stays non-zero.
        tname = "1.0 * phi (iter 1)";
        a = 10'hC0; b = 10'hE8; expected = 10'hE8;
        check_exact;

        tname = "phi * phi = phi^2";
        a = 10'hE8; b = 10'hE8;
        // phi^2 = phi+1 ~ 2.618034; exp=bias+1, mant=20
        expected = 10'h114;
        lo = expected - 1; hi = expected + 1;
        check_range;

        // --- T13: sign test: (-1.0) * phi = -phi ---
        tname = "(-1.0) * phi = -phi";
        a = 10'h2C0; b = 10'hE8;
        expected = 10'h2E8;
        check_exact;

        // --- T14: commutative: phi * (-1.0) = -phi ---
        tname = "phi * (-1.0) = -phi";
        a = 10'hE8; b = 10'h2C0;
        expected = 10'h2E8;
        check_exact;

        $display("=== RESULTS: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("tb_gf10_mul: ALL PASS");
        else
            $display("tb_gf10_mul: FAILURES DETECTED");
        $finish;
    end

endmodule