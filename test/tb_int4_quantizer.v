// SPDX-License-Identifier: Apache-2.0
// tb_int4_quantizer.v — Testbench for Int4 Quantizer
`default_nettype none
`timescale 1ns/1ps

module tb_int4_quantizer;

    reg  signed [15:0] fp16_in;
    reg  [3:0]        scale_exp;
    reg  [2:0]        zero_point;
    wire [3:0]        int4_out;

    // Quantizer
    int4_quantizer quant (
        .fp16_in(fp16_in),
        .scale_exp(scale_exp),
        .zero_point(zero_point),
        .int4_out(int4_out)
    );

    // Dequantizer
    reg  [3:0]  int4_in;
    reg  [3:0]  dequant_scale_exp;
    wire signed [15:0] fp16_out;

    int4_dequantizer dequant (
        .int4_in(int4_in),
        .scale_exp(dequant_scale_exp),
        .fp16_out(fp16_out)
    );

    // Test counters
    integer pass_count = 0;
    integer fail_count = 0;

    task check_int4;
        input [3:0] expected;
        input [100*8:1] test_name;
        begin
            if (int4_out !== expected) begin
                $display("FAIL: %s | fp16_in=%d scale=%d | got=%d expected=%d",
                         test_name, fp16_in, scale_exp, int4_out, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: %s | fp16_in=%d scale=%d | int4=%d",
                         test_name, fp16_in, scale_exp, int4_out);
                pass_count = pass_count + 1;
            end
        end
    endtask

    task check_dequant;
        input signed [15:0] expected;
        input [100*8:1] test_name;
        begin
            if (fp16_out !== expected) begin
                $display("FAIL: %s | int4_in=%d scale=%d | got=%d expected=%d",
                         test_name, int4_in, dequant_scale_exp, fp16_out, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: %s | int4_in=%d scale=%d | fp16=%d",
                         test_name, int4_in, dequant_scale_exp, fp16_out);
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_int4_quantizer.vcd");
        $dumpvars(0, tb_int4_quantizer);
        $display("=== INT4 QUANTIZER TESTBENCH ===");
        $display("Int4 range: [-8, 7], Symmetric quantization");

        zero_point = 3'd0;  // Zero-point offset (optional)

        // Test 1: Zero input
        $display("\nTest 1: Zero input");
        fp16_in = 16'd0; scale_exp = 4'd0; #1;
        check_int4(4'd8, "Zero quantization");  // 0 maps to 8 in signed Int4

        // Test 2: Positive values with scale 1.0
        $display("\nTest 2: Positive values (scale=1.0)");
        fp16_in = 16'd100; scale_exp = 4'd0; #1;
        check_int4(4'd9, "Positive 100");  // +1

        fp16_in = 16'd1000; scale_exp = 4'd0; #1;
        check_int4(4'd15, "Positive large");  // +7 (clamped)

        // Test 3: Negative values with scale 1.0
        $display("\nTest 3: Negative values (scale=1.0)");
        fp16_in = -16'd100; scale_exp = 4'd0; #1;
        check_int4(4'd7, "Negative -100");  // -1

        fp16_in = -16'd1000; scale_exp = 4'd0; #1;
        check_int4(4'd0, "Negative large");  // -8 (clamped)

        // Test 4: Scaling with different exponents
        $display("\nTest 4: Scaling");
        fp16_in = 16'd100; scale_exp = 4'd4; #1;  // Scale down by 16
        check_int4(4'd8, "Scale down (exp=4)");

        fp16_in = 16'd100; scale_exp = 4'd1; #1;  // Scale down by 2
        check_int4(4'd9, "Scale down (exp=1)");

        // Test 5: Clamping to Int4 range [-8, 7]
        $display("\nTest 5: Clamping");
        fp16_in = 16'd2000; scale_exp = 4'd0; #1;
        check_int4(4'd15, "Upper clamp (+7)");

        fp16_in = -16'd2000; scale_exp = 4'd0; #1;
        check_int4(4'd0, "Lower clamp (-8)");

        // Test 6: Dequantization
        $display("\nTest 6: Dequantization");
        int4_in = 4'd8; dequant_scale_exp = 4'd0; #1;
        check_dequant(16'd0, "Dequant zero");

        int4_in = 4'd15; dequant_scale_exp = 4'd0; #1;
        check_dequant(16'd7, "Dequant +7");

        int4_in = 4'd0; dequant_scale_exp = 4'd0; #1;
        check_dequant(-16'd8, "Dequant -8");

        // Test 7: Dequant scaling
        $display("\nTest 7: Dequant scaling");
        int4_in = 4'd15; dequant_scale_exp = 4'd2; #1;  // Scale up by 4
        check_dequant(16'd28, "Dequant scale up (exp=2)");

        int4_in = 4'd15; dequant_scale_exp = 4'd5; #1;  // Scale up by 32
        check_dequant(16'd224, "Dequant scale up (exp=5)");

        // Test 8: Round-trip quantization + dequantization
        $display("\nTest 8: Round-trip");
        // Quantize
        fp16_in = 16'd50; scale_exp = 4'd0; #1;
        int4_in = int4_out;
        // Dequantize
        dequant_scale_exp = 4'd0; #1;
        $display("Round-trip: %d -> %d -> %d", fp16_in, int4_in, fp16_out);

        // Summary
        $display("\n=== TEST SUMMARY ===");
        $display("PASS: %d", pass_count);
        $display("FAIL: %d", fail_count);
        $finish;
    end

endmodule