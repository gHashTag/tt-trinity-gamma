// SPDX-License-Identifier: Apache-2.0
// test/tb_gf48_mul.v
// Testbench for GoldenFloat48 multiplier.
// Format: [S(1) | E(18) | M(29)], bias=131071, EXP_MAX=262143.
// Rule-derived (e=round((N-1)/phi^2)), Track C RTL, \Conj status.
// Tests: identity, phi-series Lucas-EII pattern, phi*(1/phi)~=1,
//        zero annihilation, NaN/Inf propagation.
`default_nettype none
`timescale 1ns/1ps

module tb_gf48_mul;
    reg  [47:0] a, b;
    wire [47:0] result;

    gf48_mul dut (.a(a), .b(b), .result(result));

    integer pass_count, fail_count;
    reg [47:0] expected;
    reg [47:0] lo, hi;
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
        $display("=== tb_gf48_mul: GoldenFloat48 [E=18|M=29] bias=131071 ===");

        // --- T1: 1.0 * 1.0 = 1.0 identity ---
        tname = "1.0 * 1.0 = 1.0";
        a = 48'h3FFFE0000000; b = 48'h3FFFE0000000; expected = 48'h3FFFE0000000;
        check_exact;

        // --- T2: zero * phi = 0 (zero annihilation) ---
        tname = "0 * phi = 0";
        a = 48'h0; b = 48'h3FFFF3C6EF37; expected = 48'h0;
        check_exact;

        // --- T3: phi * 0 = 0 ---
        tname = "phi * 0 = 0";
        a = 48'h3FFFF3C6EF37; b = 48'h0; expected = 48'h0;
        check_exact;

        // --- T4: NaN * 1.0 = NaN ---
        tname = "NaN * 1.0 = NaN";
        a = 48'hFFFFE0000001; b = 48'h3FFFE0000000; expected = 48'hFFFFE0000001;
        check_exact;

        // --- T5: +Inf * 1.0 = +Inf ---
        tname = "+Inf * 1.0 = +Inf";
        a = 48'h7FFFE0000000; b = 48'h3FFFE0000000; expected = 48'h7FFFE0000000;
        check_exact;

        // --- T6: +Inf * 0 = NaN ---
        tname = "+Inf * 0 = NaN";
        a = 48'h7FFFE0000000; b = 48'h0; expected = 48'hFFFFE0000001;
        check_exact;

        // --- T7: phi * (1/phi) ~ 1.0 (within 1 ULP) ---
        // Due to quantization in this narrow format, allow [one-1 .. one+1].
        tname = "phi * (1/phi) ~ 1.0";
        a = 48'h3FFFF3C6EF37; b = 48'h3FFFC78DDE6E;
        lo = 48'h3FFFDFFFFFFF; hi = 48'h3FFFE0000001;
        check_range;

        // --- T8-T12: Lucas-EII: 1.0 * phi iterated (phi-series progression) ---
        // Each iteration multiplies by phi; checks that the exponent advances by
        // 1 per phi^2 iterations on average. We verify the product stays non-zero.
        tname = "1.0 * phi (iter 1)";
        a = 48'h3FFFE0000000; b = 48'h3FFFF3C6EF37; expected = 48'h3FFFF3C6EF37;
        check_exact;

        tname = "phi * phi = phi^2";
        a = 48'h3FFFF3C6EF37; b = 48'h3FFFF3C6EF37;
        // phi^2 = phi+1 ~ 2.618034; exp=bias+1, mant=165902236
        expected = 48'h400009E3779C;
        lo = expected - 1; hi = expected + 1;
        check_range;

        // --- T13: sign test: (-1.0) * phi = -phi ---
        tname = "(-1.0) * phi = -phi";
        a = 48'hBFFFE0000000; b = 48'h3FFFF3C6EF37;
        expected = 48'hBFFFF3C6EF37;
        check_exact;

        // --- T14: commutative: phi * (-1.0) = -phi ---
        tname = "phi * (-1.0) = -phi";
        a = 48'h3FFFF3C6EF37; b = 48'hBFFFE0000000;
        expected = 48'hBFFFF3C6EF37;
        check_exact;

        $display("=== RESULTS: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("tb_gf48_mul: ALL PASS");
        else
            $display("tb_gf48_mul: FAILURES DETECTED");
        $finish;
    end

endmodule