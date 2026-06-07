// SPDX-License-Identifier: Apache-2.0
// test/tb_gf96_mul.v
// Testbench for GoldenFloat96 multiplier.
// Format: [S(1) | E(36) | M(59)], bias=34359738367, EXP_MAX=68719476735.
// Rule-derived (e=round((N-1)/phi^2)), Track C RTL, \Conj status.
// Note: GF96 has a 120-bit intermediate product (SYNTHESIS_WARN).
// Tests: identity, phi-series Lucas-EII pattern, phi*(1/phi)~=1,
//        zero annihilation, NaN/Inf propagation.
// Expected values pre-validated by Python RTL model (exact bit match).
`default_nettype none
`timescale 1ns/1ps

module tb_gf96_mul;
    reg  [95:0] a, b;
    wire [95:0] result;

    gf96_mul dut (.a(a), .b(b), .result(result));

    integer pass_count, fail_count;
    reg [95:0] expected;
    reg [95:0] lo, hi;
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
        $display("=== tb_gf96_mul: GoldenFloat96 [E=36|M=59] bias=34359738367 ===");

        // --- T1: 1.0 * 1.0 = 1.0 identity ---
        tname = "1.0 * 1.0 = 1.0";
        a = 96'h3FFFFFFFF800000000000000; b = 96'h3FFFFFFFF800000000000000; expected = 96'h3FFFFFFFF800000000000000;
        check_exact;

        // --- T2: zero * phi = 0 (zero annihilation) ---
        tname = "0 * phi = 0";
        a = 96'h0; b = 96'h3FFFFFFFFCF1BBCDCBFA5400; expected = 96'h0;
        check_exact;

        // --- T3: phi * 0 = 0 ---
        tname = "phi * 0 = 0";
        a = 96'h3FFFFFFFFCF1BBCDCBFA5400; b = 96'h0; expected = 96'h0;
        check_exact;

        // --- T4: NaN * 1.0 = NaN ---
        tname = "NaN * 1.0 = NaN";
        a = 96'hFFFFFFFFF800000000000001; b = 96'h3FFFFFFFF800000000000000; expected = 96'hFFFFFFFFF800000000000001;
        check_exact;

        // --- T5: +Inf * 1.0 = +Inf ---
        tname = "+Inf * 1.0 = +Inf";
        a = 96'h7FFFFFFFF800000000000000; b = 96'h3FFFFFFFF800000000000000; expected = 96'h7FFFFFFFF800000000000000;
        check_exact;

        // --- T6: +Inf * 0 = NaN ---
        tname = "+Inf * 0 = NaN";
        a = 96'h7FFFFFFFF800000000000000; b = 96'h0; expected = 96'hFFFFFFFFF800000000000001;
        check_exact;

        // --- T7: phi * (1/phi) ~ 1.0 ---
        // Due to independent quantization of phi and 1/phi (each to 59 mantissa bits),
        // the product deviates from 1.0 by ~67 ULPs. Expected value confirmed by
        // Python RTL model. Range allows +-2 ULPs of the confirmed value.
        tname = "phi * (1/phi) ~ 1.0";
        a = 96'h3FFFFFFFFCF1BBCDCBFA5400; b = 96'h3FFFFFFFF1E3779B97F4A780;
        lo = 96'h3FFFFFFFF7FFFFFFFFFFFFBB; hi = 96'h3FFFFFFFF7FFFFFFFFFFFFBF;  // confirmed: 0x3FFFFFFFF7FFFFFFFFFFFFBD
        check_range;

        // --- T8: 1.0 * phi = phi (Lucas-EII step 1) ---
        tname = "1.0 * phi (iter 1)";
        a = 96'h3FFFFFFFF800000000000000; b = 96'h3FFFFFFFFCF1BBCDCBFA5400; expected = 96'h3FFFFFFFFCF1BBCDCBFA5400;
        check_exact;

        // --- T9: phi * phi = phi^2 ---
        // phi^2 = phi+1 ~ 2.6180...; exp=bias+1.
        // Confirmed value: 0x400000000278DDE6E5FD2A23 (Python RTL model).
        tname = "phi * phi = phi^2";
        a = 96'h3FFFFFFFFCF1BBCDCBFA5400; b = 96'h3FFFFFFFFCF1BBCDCBFA5400;
        lo = 96'h400000000278DDE6E5FD2A22; hi = 96'h400000000278DDE6E5FD2A24;
        check_range;

        // --- T10: sign test: (-1.0) * phi = -phi ---
        tname = "(-1.0) * phi = -phi";
        a = 96'hBFFFFFFFF800000000000000; b = 96'h3FFFFFFFFCF1BBCDCBFA5400;
        expected = 96'hBFFFFFFFFCF1BBCDCBFA5400;
        check_exact;

        // --- T11: commutative: phi * (-1.0) = -phi ---
        tname = "phi * (-1.0) = -phi";
        a = 96'h3FFFFFFFFCF1BBCDCBFA5400; b = 96'hBFFFFFFFF800000000000000;
        expected = 96'hBFFFFFFFFCF1BBCDCBFA5400;
        check_exact;

        $display("=== RESULTS: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("tb_gf96_mul: ALL PASS");
        else
            $display("tb_gf96_mul: FAILURES DETECTED");
        $finish;
    end

endmodule