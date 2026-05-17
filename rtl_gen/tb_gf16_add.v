// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/tb_gf16_add.v
// Testbench for GF16 Addition Unit

`timescale 1ns / 1ps

module tb_gf16_add;
    reg clk;
    reg rst_n;
    reg [15:0] a;
    reg [15:0] b;
    wire [15:0] result;

    gf16_add dut (
        .a(a),
        .b(b),
        .result(result)
    );

    // Test vectors (phi identity tests)
    reg [15:0] test_a [0:7];
    reg [15:0] test_b [0:7];
    reg [15:0] expected [0:7];
    string test_name [0:7][80:1];

    integer i;
    integer errors;

    // Clock generation
    initial clk = 0;
    always #2.5 clk = ~clk;  // 400 MHz

    initial begin
        $dumpfile("tb_gf16_add.vcd");
        $dumpvars(0, tb_gf16_add);

        // Initialize
        rst_n = 0;
        a = 16'h0000;
        b = 16'h0000;
        errors = 0;

        // Set up test vectors
        test_name[0] = "zero_plus_zero";
        test_a[0] = 16'h0000;  // +0.0
        test_b[0] = 16'h0000;  // +0.0
        expected[0] = 16'h0000; // +0.0

        test_name[1] = "one_plus_one";
        test_a[1] = 16'h3E80;  // +1.0
        test_b[1] = 16'h3E80;  // +1.0
        expected[1] = 16'h7E00;  // +2.0

        test_name[2] = "phi_times_phi";
        test_a[2] = 16'h3ECC;  // φ ≈ 1.618
        test_b[2] = 16'h3ECC;  // φ ≈ 1.618
        expected[2] = 16'h7E6C;  // φ² ≈ 2.618 (may need rounding)

        // Reset sequence
        #10 rst_n = 0;
        #20 rst_n = 1;

        // Run tests
        @(negedge rst_n);
        @(posedge rst_n);

        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            a = test_a[i];
            b = test_b[i];
            @(posedge clk);
            
            if (result !== expected[i]) begin
                $display("ERROR: %s", test_name[i]);
                $display("  Expected: 0x%04X", expected[i]);
                $display("  Got:      0x%04X", result);
                errors = errors + 1;
            end else begin
                $display("PASS: %s", test_name[i]);
            end
        end

        // Summary
        $display("");
        $display("=== Test Summary ===");
        $display("Total: 8, Passed: %0d, Failed: %0d", 8 - errors, errors);

        if (errors == 0) begin
            $display("SUCCESS: All tests passed!");
        end else begin
            $display("FAILURE: Some tests failed!");
        end

        $finish;
    end

endmodule
