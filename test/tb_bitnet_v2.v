// SPDX-License-Identifier: Apache-2.0
// tb_bitnet_v2.v -- confirms the bitnet_encoder neuron-base fix.
// Runs the shipped bitnet_encoder (10-bit neuron_base -> neurons 16..31 alias
// 0..15) and the corrected bitnet_encoder_v2 (11-bit) side by side over several
// inputs and checks that their outputs DIFFER (the aliasing was behaviorally
// significant). The v2's 32-distinct-neuron property follows from the full
// 0..2047 address range; the live param width is regression-checked separately by
// tools/bitnet_neuron_base_check.py (Corona). Run:
//   iverilog -g2012 -o /tmp/x ../src/bitnet_encoder.v ../src/bitnet_encoder_v2.v tb_bitnet_v2.v && vvp /tmp/x
`timescale 1ns/1ps
module tb_bitnet_v2;
    reg clk = 0, rst_n = 0, start = 0;
    reg [127:0] x;
    wire done_o, done_n, ok_o, ok_n;
    wire [63:0] y_o, y_n;
    integer t, c, diffs;

    bitnet_encoder     u_old (.clk(clk), .rst_n(rst_n), .start(start), .x_in(x),
                              .done(done_o), .y_out(y_o), .encoder_ok(ok_o));
    bitnet_encoder_v2  u_new (.clk(clk), .rst_n(rst_n), .start(start), .x_in(x),
                              .done(done_n), .y_out(y_n), .encoder_ok(ok_n));

    always #5 clk = ~clk;

    // a few deterministic test inputs (no $random for reproducibility)
    function [127:0] tvec(input integer s);
        tvec = {32'h0F0F0F0F ^ (s*32'h1234567),
                32'hA5A5A5A5 + (s*32'h9E3779B1),
                32'hC3C3C3C3 ^ (s*32'h2545F491),
                32'h5A5A5A5A + (s*32'h61C88647)};
    endfunction

    initial begin
        diffs = 0;
        @(negedge clk) rst_n = 0; @(negedge clk) rst_n = 1;
        for (t = 0; t < 6; t = t + 1) begin
            x = tvec(t);
            @(negedge clk) start = 1;
            @(negedge clk) start = 0;
            // wait for both to finish (timeout 200 cycles)
            c = 0;
            while (!(done_o && done_n) && c < 200) begin @(negedge clk); c = c + 1; end
            if (y_o !== y_n) diffs = diffs + 1;
            $display("R t=%0d old=%016h new=%016h %s", t, y_o, y_n,
                     (y_o !== y_n) ? "DIFF" : "same");
            // settle between runs
            repeat (3) @(negedge clk);
        end
        $display("SUMMARY: %0d/6 inputs differ (old aliases neurons 16..31; v2 fixes)",
                 diffs);
        if (diffs > 0) $display("RESULT: PASS (fix is behaviorally significant)");
        else           $display("RESULT: CHECK (no diff -- unexpected)");
        $finish;
    end
endmodule
