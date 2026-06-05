// SPDX-License-Identifier: Apache-2.0
// tb_integration_mesh.v — Integration test for GF16 mesh routing
// Tests packet flow through trinity_max_true_20pe.
//
// FIX (2026-06): this TB previously defined its OWN local packet macros that
// CONTRADICTED the real src/trinity_packet.vh -- TRN_MK_PKT inserted an extra
// 3'b0 (a 35-bit packet, truncated/misaligned) and TRN_OP_READ_RES was 4'd6
// (the real READ_RES is 4'h5; 4'd6 is RECEIPT). So it read back 0x0000 and
// "failed" for harness reasons, never exercising the RTL. It is also NOT wired
// into CI, so the rot went unnoticed. Now it includes the canonical header and
// uses the real opcodes; the canonical dot4 returns 0x47C0 (= 30.0 in GF16).
// Compile with: iverilog -g2012 -I src src/*.v test/tb_integration_mesh.v

`default_nettype none
`timescale 1ns/1ps
`include "trinity_packet.vh"

module tb_integration_mesh;

    reg clk;
    reg rst_n;

    reg  [`TRN_PKT_W-1:0] host_in_pkt;
    reg                   host_in_valid;
    wire                  host_in_ready;
    wire [`TRN_PKT_W-1:0] host_out_pkt;
    wire                  host_out_valid;
    reg                   host_out_ready;
    wire [15:0]           dbg_tile0;

    // DUT is the 2x2 mesh fabric this test is named for (host->router->tile->
    // dot->tile->router->host). The full trinity_max_true_20pe top adds cluster
    // selection on lane[3] and is exercised by the TT canonical test pattern.
    trinity_mesh_2x2 dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (host_in_valid),
        .host_in_ready   (host_in_ready),
        .host_out_pkt    (host_out_pkt),
        .host_out_valid  (host_out_valid),
        .host_out_ready  (host_out_ready),
        .dbg_tile0_result(dbg_tile0)
    );

    initial begin clk = 0; forever #10 clk = ~clk; end  // 50 MHz

    integer pass_count = 0;
    integer fail_count = 0;

    task check_result;
        input [15:0] expected;
        input [100*8:1] test_name;
        begin
            if (dbg_tile0 !== expected) begin
                $display("FAIL: %0s | got=%h expected=%h", test_name, dbg_tile0, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: %0s | result=%h", test_name, dbg_tile0);
                pass_count = pass_count + 1;
            end
        end
    endtask

    task send_pkt;
        input [`TRN_PKT_W-1:0] pkt;
        begin
            host_in_pkt = pkt;
            host_in_valid = 1'b1;
            @(posedge clk);
            while (!host_in_ready) @(posedge clk);
            host_in_valid = 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        $display("=== INTEGRATION TEST: GF16 MESH ROUTING ===");

        rst_n = 0;
        host_in_valid = 1'b0;
        host_out_ready = 1'b1;
        #100; rst_n = 1; #100;

        // Test 1: canonical dot4([1,2,3,4].[1,2,3,4]) = 30.0 = 0x47C0
        // lane[3]=pkt[23]=0 (lanes 0..3) -> cluster 0 quad-mesh, dbg = tile 0.
        $display("\nTest 1: Single tile load-compute-read");
        send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_A, 2'd0, 2'd0, 4'd0, 16'h3E00)); // 1.0
        send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_A, 2'd0, 2'd0, 4'd1, 16'h4000)); // 2.0
        send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_A, 2'd0, 2'd0, 4'd2, 16'h4100)); // 3.0
        send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_A, 2'd0, 2'd0, 4'd3, 16'h4200)); // 4.0
        send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_B, 2'd0, 2'd0, 4'd0, 16'h3E00));
        send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_B, 2'd0, 2'd0, 4'd1, 16'h4000));
        send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_B, 2'd0, 2'd0, 4'd2, 16'h4100));
        send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_B, 2'd0, 2'd0, 4'd3, 16'h4200));
        send_pkt(`TRN_MK_PKT(`TRN_OP_COMPUTE,  2'd0, 2'd0, 4'd0, 16'h0000));
        send_pkt(`TRN_MK_PKT(`TRN_OP_READ_RES, 2'd0, 2'd0, 4'd0, 16'h0000));
        repeat (8) @(posedge clk);
        check_result(16'h47C0, "Canonical dot4(1,2,3,4)");

        $display("\n=== TEST SUMMARY ===");
        $display("PASS: %0d", pass_count);
        $display("FAIL: %0d", fail_count);
        if (fail_count != 0) $fatal(1, "integration mesh test failed");
        $finish;
    end

endmodule
