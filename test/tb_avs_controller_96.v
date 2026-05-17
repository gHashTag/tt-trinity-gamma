// SPDX-License-Identifier: Apache-2.0
// tb_avs_controller_96.v — Testbench for AVS-96 Controller
`default_nettype none
`timescale 1ns/1ps

module tb_avs_controller_96;

    reg        clk;
    reg        rst_n;
    reg [95:0] power_req;
    reg [5:0]  therm_mon;
    reg        avs_enable;
    wire [191:0] voltage_level;
    wire [5:0]  therm_warning;
    wire        power_gate;

    avs_controller_96 dut (
        .clk(clk),
        .rst_n(rst_n),
        .power_req(power_req),
        .therm_mon(therm_mon),
        .avs_enable(avs_enable),
        .voltage_level(voltage_level),
        .therm_warning(therm_warning),
        .power_gate(power_gate)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100 MHz
    end

    // Voltage level extraction helper
    function [1:0] get_voltage;
        input [5:0] island;
        begin
            get_voltage = {voltage_level[island*2+1], voltage_level[island*2]};
        end
    endfunction

    // Test counters
    integer pass_count = 0;
    integer fail_count = 0;

    task check_voltage;
        input [5:0] island;
        input [1:0] expected;
        input [100*8:1] test_name;
        reg [1:0] actual;
        begin
            actual = get_voltage(island);
            if (actual !== expected) begin
                $display("FAIL: %s | island=%d | got=%d expected=%d", test_name, island, actual, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: %s | island=%d | voltage=%d", test_name, island, actual);
                pass_count = pass_count + 1;
            end
        end
    endtask

    task check_power_gate;
        input expected;
        input [100*8:1] test_name;
        begin
            if (power_gate !== expected) begin
                $display("FAIL: %s | got=%d expected=%d", test_name, power_gate, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: %s | power_gate=%d", test_name, power_gate);
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_avs_controller_96.vcd");
        $dumpvars(0, tb_avs_controller_96);
        $display("=== AVS-96 CONTROLLER TESTBENCH ===");

        // Initialize
        rst_n = 0;
        power_req = 96'h0;
        therm_mon = 6'd0;
        avs_enable = 1'b0;
        #20;
        rst_n = 1;

        // Test 1: Reset state
        $display("\nTest 1: Reset state");
        #10;
        check_voltage(6'd0, 2'b00, "Island 0 reset voltage");
        check_power_gate(1'b0, "Reset power gate off");

        // Test 2: Enable AVS
        $display("\nTest 2: Enable AVS");
        avs_enable = 1'b1;
        repeat(5) @(posedge clk);

        // Test 3: Low power request (should set 0.75V)
        $display("\nTest 3: Low power request");
        power_req = {96{6'd5}};  // All islands at low power
        repeat(20) @(posedge clk);
        check_voltage(6'd0, 2'b00, "Island 0 at 0.75V");
        check_voltage(6'd50, 2'b00, "Island 50 at 0.75V");

        // Test 4: Medium power request (should set 0.85V)
        $display("\nTest 4: Medium power request");
        power_req = {96{6'd20}};  // All islands at medium power
        repeat(20) @(posedge clk);
        check_voltage(6'd0, 2'b01, "Island 0 at 0.85V");
        check_voltage(6'd95, 2'b01, "Island 95 at 0.85V");

        // Test 5: High power request (should set 0.95V)
        $display("\nTest 5: High power request");
        power_req = {96{6'd40}};  // All islands at high power
        repeat(20) @(posedge clk);
        check_voltage(6'd0, 2'b10, "Island 0 at 0.95V");
        check_voltage(6'd30, 2'b10, "Island 30 at 0.95V");

        // Test 6: Max power request (should set 1.05V)
        $display("\nTest 6: Max power request");
        power_req = {96{6'd63}};  // All islands at max power
        repeat(20) @(posedge clk);
        check_voltage(6'd0, 2'b11, "Island 0 at 1.05V");
        check_voltage(6'd95, 2'b11, "Island 95 at 1.05V");

        // Test 7: Mixed power requests
        $display("\nTest 7: Mixed power requests");
        power_req = 96'h0;
        power_req[3:0] = 6'd5;    // Low
        power_req[7:4] = 6'd20;   // Medium
        power_req[11:8] = 6'd40;  // High
        power_req[15:12] = 6'd63; // Max
        repeat(20) @(posedge clk);
        check_voltage(6'd0, 2'b00, "Mixed island 0 at 0.75V");
        check_voltage(6'd1, 2'b01, "Mixed island 1 at 0.85V");
        check_voltage(6'd2, 2'b10, "Mixed island 2 at 0.95V");
        check_voltage(6'd3, 2'b11, "Mixed island 3 at 1.05V");

        // Test 8: Thermal warning (should reduce voltage)
        $display("\nTest 8: Thermal warning");
        therm_mon = 6'd55;  // Warning threshold
        power_req = {96{6'd63}};
        repeat(20) @(posedge clk);
        check_voltage(6'd0, 2'b01, "Thermal warning: island 0 at 0.85V");
        check_power_gate(1'b0, "Thermal warning: power gate off");

        // Test 9: Critical thermal (should power gate)
        $display("\nTest 9: Critical thermal - power gate");
        therm_mon = 6'd60;  // Critical threshold
        repeat(20) @(posedge clk);
        check_power_gate(1'b1, "Critical thermal: power gate ON");
        check_voltage(6'd0, 2'b00, "Critical thermal: island 0 at 0.75V");

        // Test 10: Thermal recovery
        $display("\nTest 10: Thermal recovery");
        therm_mon = 6'd40;  // Normal temperature
        repeat(30) @(posedge clk);
        check_power_gate(1'b0, "Thermal recovery: power gate OFF");
        check_voltage(6'd0, 2'b11, "Thermal recovery: back to 1.05V");

        // Summary
        $display("\n=== TEST SUMMARY ===");
        $display("PASS: %d", pass_count);
        $display("FAIL: %d", fail_count);
        $finish;
    end

endmodule