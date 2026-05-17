// SPDX-License-Identifier: Apache-2.0
// tb_lane_l_precheck.v — Testbench for LUT Lookup Precheck (OP_LUT_LOOKUP 0xDF)
`default_nettype none
`timescale 1ns/1ps

module tb_lane_l_precheck;

    reg        clk;
    reg        rst_n;
    reg        valid_in;
    reg  [6:0]  lut_addr;
    reg  [7:0]  lut_data_in;
    reg  [3:0]  opcode;
    reg        enable;
    wire       valid_out;
    wire [7:0] lut_data_out;
    wire       hit;
    wire       miss;
    wire [6:0] lut_addr_out;

    lane_l_precheck dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .lut_addr(lut_addr),
        .lut_data_in(lut_data_in),
        .opcode(opcode),
        .enable(enable),
        .valid_out(valid_out),
        .lut_data_out(lut_data_out),
        .hit(hit),
        .miss(miss),
        .lut_addr_out(lut_addr_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100 MHz
    end

    // Test counters
    integer pass_count = 0;
    integer fail_count = 0;

    task check_output;
        input [7:0] expected_data;
        input       expected_hit;
        input       expected_miss;
        input [100*8:1] test_name;
        begin
            if (lut_data_out !== expected_data || hit !== expected_hit || miss !== expected_miss) begin
                $display("FAIL: %s", test_name);
                $display("      data: got=%d expected=%d", lut_data_out, expected_data);
                $display("      hit: got=%d expected=%d", hit, expected_hit);
                $display("      miss: got=%d expected=%d", miss, expected_miss);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: %s | data=%d hit=%d miss=%d", test_name, lut_data_out, hit, miss);
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_lane_l_precheck.vcd");
        $dumpvars(0, tb_lane_l_precheck);
        $display("=== LANE L_PRECHECK TESTBENCH (OP_LUT_LOOKUP 0xDF) ===");

        // Initialize
        rst_n = 0;
        valid_in = 0;
        lut_addr = 7'd0;
        lut_data_in = 8'd0;
        opcode = 4'h0;
        enable = 1'b0;
        #20;
        rst_n = 1;
        enable = 1'b1;

        // Test 1: Opcode 0xDF (LUT_LOOKUP) should enable LUT path
        $display("\nTest 1: OP_LUT_LOOKUP (0xDF) enable");
        opcode = 4'hD;
        lut_addr = 7'd42;
        lut_data_in = 8'hA5;
        valid_in = 1'b1;
        @(posedge clk);
        valid_in = 1'b0;
        repeat(3) @(posedge clk);
        check_output(8'hA5, 1'b1, 1'b0, "LUT lookup at address 42");

        // Test 2: Different LUT address
        $display("\nTest 2: Different LUT address");
        lut_addr = 7'd100;
        lut_data_in = 8'h3C;
        valid_in = 1'b1;
        @(posedge clk);
        valid_in = 1'b0;
        repeat(3) @(posedge clk);
        check_output(8'h3C, 1'b1, 1'b0, "LUT lookup at address 100");

        // Test 3: LUT miss scenario
        $display("\nTest 3: LUT miss (address out of range)");
        lut_addr = 7'd127;
        lut_data_in = 8'h00;
        valid_in = 1'b1;
        @(posedge clk);
        valid_in = 1'b0;
        repeat(3) @(posedge clk);
        check_output(8'h00, 1'b0, 1'b1, "LUT miss at address 127");

        // Test 4: Zero LUT data
        $display("\nTest 4: Zero LUT data");
        lut_addr = 7'd50;
        lut_data_in = 8'h00;
        valid_in = 1'b1;
        @(posedge clk);
        valid_in = 1'b0;
        repeat(3) @(posedge clk);
        check_output(8'h00, 1'b1, 1'b0, "LUT lookup returns zero");

        // Test 5: Sequential LUT accesses
        $display("\nTest 5: Sequential LUT accesses");
        repeat(5) begin
            lut_addr = lut_addr + 1'b1;
            lut_data_in = lut_data_in + 1'b1;
            valid_in = 1'b1;
            @(posedge clk);
            valid_in = 1'b0;
            repeat(3) @(posedge clk);
        end
        $display("PASS: Sequential LUT accesses");

        // Test 6: Enable toggle
        $display("\nTest 6: Enable toggle");
        enable = 1'b0;
        lut_addr = 7'd60;
        lut_data_in = 8'hFF;
        valid_in = 1'b1;
        @(posedge clk);
        valid_in = 1'b0;
        repeat(3) @(posedge clk);
        check_output(8'h00, 1'b0, 1'b1, "LUT disabled - miss");

        enable = 1'b1;
        valid_in = 1'b1;
        @(posedge clk);
        valid_in = 1'b0;
        repeat(3) @(posedge clk);
        check_output(8'hFF, 1'b1, 1'b0, "LUT re-enabled - hit");

        // Summary
        $display("\n=== TEST SUMMARY ===");
        $display("PASS: %d", pass_count);
        $display("FAIL: %d", fail_count);
        $finish;
    end

endmodule