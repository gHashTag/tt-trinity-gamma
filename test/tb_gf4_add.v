// SPDX-License-Identifier: Apache-2.0
// tb_gf4_add.v — Testbench for GF4 addition
`default_nettype none
`timescale 1ns/1ps

module tb_gf4_add;
    reg  [3:0] a, b;
    wire [3:0] result;

    gf4_add dut (
        .a(a),
        .b(b),
        .result(result)
    );

    // Test vectors
    reg [3:0] expected;
    reg [100*8:1] test_name;

    task check;
        begin
            if (result !== expected) begin
                $display("FAIL: %s | a=%b b=%b | got=%b expected=%b", test_name, a, b, result, expected);
                $display("      (a=0x%h b=0x%h | got=0x%h expected=0x%h)", a, b, result, expected);
            end else begin
                $display("PASS: %s | a=0x%h b=0x%h | result=0x%h", test_name, a, b, result);
            end
        end
    endtask

    // GF4 format: [S(1) | E(1) | M(2)] - BIAS = 0
    // Normal numbers: exp=1, mant=0..3 => value = 2^(1-0) * (1 + mant/4) = 2 * (1 + m/4)
    // mant=0: 2 * 1.0 = 2.0
    // mant=1: 2 * 1.25 = 2.5
    // mant=2: 2 * 1.5 = 3.0
    // mant=3: 2 * 1.75 = 3.5

    initial begin
        $dumpfile("tb_gf4_add.vcd");
        $dumpvars(0, tb_gf4_add);
        $display("=== GF4 ADDITION TESTBENCH ===");
        $display("Format: [S(1) | E(1) | M(2)] - BIAS = 0");

        // Test 1: Zero + Zero = Zero
        test_name = "Zero + Zero";
        a = 4'h0; b = 4'h0; expected = 4'h0; #10; check;

        // Test 2: 2.0 + 2.0 = 4.0 (overflow to Inf)
        // a=0b0100 (2.0), b=0b0100 (2.0), expected=0b0100 (Inf positive)
        test_name = "2.0 + 2.0 = Inf";
        a = 4'h4; b = 4'h4; expected = 4'h4; #10; check;

        // Test 3: 2.0 + (-2.0) = Zero (cancel)
        // a=0b0100 (2.0), b=0b1100 (-2.0)
        test_name = "2.0 + (-2.0) = Zero";
        a = 4'h4; b = 4'hC; expected = 4'h0; #10; check;

        // Test 4: 2.5 + 2.0 = 4.5 (overflow)
        // a=0b0101 (2.5), b=0b0100 (2.0)
        test_name = "2.5 + 2.0 = Inf";
        a = 4'h5; b = 4'h4; expected = 4'h4; #10; check;

        // Test 5: 3.0 + (-2.5) = 0.5 (underflow)
        // a=0b0110 (3.0), b=0b1101 (-2.5)
        test_name = "3.0 + (-2.5) = Underflow";
        a = 4'h6; b = 4'hD; expected = 4'h0; #10; check;

        // Test 6: 2.5 + 0 = 2.5
        test_name = "2.5 + Zero = 2.5";
        a = 4'h5; b = 4'h0; expected = 4'h5; #10; check;

        // Test 7: Zero + 3.5 = 3.5
        test_name = "Zero + 3.5 = 3.5";
        a = 4'h0; b = 4'h7; expected = 4'h7; #10; check;

        // Test 8: NaN propagation
        // GF4 NaN pattern: 0b1110 (sign=1, exp=1, mant=2)
        test_name = "NaN + 2.0 = NaN";
        a = 4'hE; b = 4'h4; expected = 4'hE; #10; check;

        // Test 9: Inf + 2.0 = Inf
        test_name = "Inf + 2.0 = Inf";
        a = 4'h4; b = 4'h4; expected = 4'h4; #10; check;

        // Test 10: Inf + (-Inf) = NaN
        test_name = "Inf + (-Inf) = NaN";
        a = 4'h4; b = 4'hC; expected = 4'hE; #10; check;

        // Test 11: (-2.5) + (-2.0) = (-4.5) = -Inf
        test_name = "(-2.5) + (-2.0) = -Inf";
        a = 4'hD; b = 4'hC; expected = 4'hC; #10; check;

        $display("=== ALL TESTS COMPLETE ===");
        $finish;
    end

endmodule