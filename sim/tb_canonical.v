`default_nettype none
`timescale 1ns / 1ps
// TRI-1 MAX-TRUE FLAGSHIP canonical anchor smoke test (iverilog stand-alone).
// Apache-2.0
//
// TG-TRIAD-X (PhD Theorem 36.1): cross-die canonical equality
//   uo_out||uio_out == 0x47C0 across {Nano, Mid, MAX-TRUE} after reset,
//   load_mode=0, before mesh result_valid_q asserts.

module tb_canonical;
    reg clk = 0;
    reg rst_n = 0;
    reg ena = 1;
    reg [7:0] ui_in = 0;
    reg [7:0] uio_in = 0;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_trinity_max_true dut (
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    always #10 clk = ~clk;  // 50 MHz

    integer pass = 0, fail = 0;
    wire [15:0] result = {uio_out, uo_out};

    initial begin
        $dumpfile("tb_canonical.vcd");
        $dumpvars(0, tb_canonical);

        // Reset
        rst_n = 0;
        #100;
        rst_n = 1;
        #20;

        // T1: canonical 0x47C0 after reset
        if (result == 16'h47C0) begin
            $display("[T1] PASS canonical 0x47C0 = 0x%04h", result);
            pass = pass + 1;
        end else begin
            $display("[T1] FAIL expected 0x47C0 got 0x%04h", result);
            fail = fail + 1;
        end

        // T2: uio_oe == 0xFF
        if (uio_oe == 8'hFF) begin
            $display("[T2] PASS uio_oe = 0x%02h", uio_oe);
            pass = pass + 1;
        end else begin
            $display("[T2] FAIL uio_oe = 0x%02h", uio_oe);
            fail = fail + 1;
        end

        // T3: 0x47C0 stable across 20 cycles (mesh path hasn't asserted yet)
        begin : t3_block
            integer i;
            reg stable;
            stable = 1;
            for (i = 0; i < 20; i = i + 1) begin
                @(posedge clk);
                if (result != 16'h47C0) begin
                    stable = 0;
                    $display("[T3] FAIL drift at cycle %0d: 0x%04h", i, result);
                end
            end
            if (stable) begin
                $display("[T3] PASS 0x47C0 stable across 20 cycles");
                pass = pass + 1;
            end else begin
                fail = fail + 1;
            end
        end

        $display("");
        $display("TB_CANONICAL: %0d PASS, %0d FAIL", pass, fail);
        if (fail == 0) $display("RESULT: ALL PASS (%0d/3)", pass);
        else           $display("RESULT: FAILED");
        $finish;
    end

    // Hang guard
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
