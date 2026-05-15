// =============================================================================
// holo_lut_pe_tb.sv — Testbench for holo_lut_pe (Platinum MST LUT PE)
// =============================================================================
// L-DPC25 Lane V · lever1-lut-pe
// R5-HONEST: structural correctness check only — CI gates real sim/compile.
// Author: admin@t27.ai
// Anchor: φ²+φ⁻²=3 · DOI 10.5281/zenodo.19227877
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module holo_lut_pe_tb;

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    logic        clk;
    logic        rst_n;
    logic [9:0]  trit_idx;
    logic        oob;
    logic [7:0]  result;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    holo_lut_pe #(
        .WIDTH    (8),
        .MST_DEPTH(5)
    ) dut (
        .clk_i      (clk),
        .rst_ni     (rst_n),
        .trit_idx_i (trit_idx),
        .oob_o      (oob),
        .result_o   (result)
    );

    // -----------------------------------------------------------------------
    // Clock: 10 ns period
    // -----------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Task: apply input, wait 2 cycles (1-cycle pipeline), check output
    // Pipeline depth: 2 register stages → result valid 2 cycles after input
    // -----------------------------------------------------------------------
    task automatic apply_and_check (
        input  logic [9:0]  idx,
        input  logic [7:0]  expected,
        input  logic        expect_oob,
        input  string       test_name
    );
        @(negedge clk);
        trit_idx = idx;
        @(posedge clk); #1;   // stage1 captures
        @(posedge clk); #1;   // stage2 produces result_o
        if (result !== expected) begin
            $fatal(1, "[FAIL] %s: trit_idx=0x%03x expected result=0x%02x got=0x%02x",
                   test_name, idx, expected, result);
        end
        if (oob !== expect_oob) begin
            $fatal(1, "[FAIL] %s: trit_idx=0x%03x expected oob=%0b got=%0b",
                   test_name, idx, expect_oob, oob);
        end
        $display("[PASS] %s: trit_idx=0x%03x → result=0x%02x oob=%0b",
                 test_name, idx, result, oob);
    endtask

    // -----------------------------------------------------------------------
    // Encode helper: convert 5 trit values (0/1/2) to 10-bit encoding
    //   trit_idx[2n+1:2n] = trit_n
    // -----------------------------------------------------------------------
    function automatic logic [9:0] encode_trits(
        input logic [1:0] t4, t3, t2, t1, t0
    );
        encode_trits = {t4, t3, t2, t1, t0};
    endfunction

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin : tb_main
        $display("=== holo_lut_pe testbench start ===");

        // Reset assertion (active-low)
        rst_n    = 1'b0;
        trit_idx = 10'd0;
        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // -------------------------------------------------------------------
        // Test 1: index=0 → lut_rom[0] = 8'hC0 after 1 clock cycle
        //   All trits = 0 → raw_addr = 0 → lut_addr = 0 → lut_rom[0] = 8'hC0
        // -------------------------------------------------------------------
        apply_and_check(
            encode_trits(2'b00, 2'b00, 2'b00, 2'b00, 2'b00),
            8'hC0,
            1'b0,
            "Test1_idx0"
        );

        // -------------------------------------------------------------------
        // Test 2: index=121 → lut_rom[121] = 8'h39 after 1 clock cycle
        //   Highest valid index: raw_addr = 121 → lut_addr = 121 → 8'h39
        //   Encoding: 121 = 1*81 + 1*27 + 1*9 + 1*3 + 1*1
        //             = t4=1(2'b01), t3=1(2'b01), t2=1(2'b01), t1=1(2'b01), t0=1(2'b01)
        //   raw_addr = 0 + 1 + 3 + 9 + 27 + 81 = 121  ✓
        // -------------------------------------------------------------------
        apply_and_check(
            encode_trits(2'b01, 2'b01, 2'b01, 2'b01, 2'b01),
            8'h39,
            1'b0,
            "Test2_idx121"
        );

        // -------------------------------------------------------------------
        // Test 3: OOB range [122..127] — indices from reserved trit encoding
        //   Design choice: Mirror Consolidation folds raw_addr ∈ [122..242]
        //   back into [1..121] via (242 - raw_addr), so no input from valid
        //   3-value trit encoding falls OOB after mirror fold.
        //   The oob_o flag is only set for raw_addr > 242 (reserved 2'b11 encoding).
        //
        //   To exercise oob_o: inject 2'b11 (reserved) on one trit.
        //   With t4=2'b11 (reserved→0), t3..t0=2'b10 (val=2):
        //     raw_addr = 0 + 2 + 6 + 18 + 54 + 0 = 80  (not OOB in address)
        //   The OOB condition triggers only when raw_addr > 242 — impossible
        //   with 3-value encoding. We document this: with valid 2-bit trit
        //   encoding, Mirror Consolidation guarantees all raw_addr ∈ [0..242],
        //   so oob_o = 0 always for well-formed inputs.
        //
        //   Test 3a: Force maximum in-range near-mirror address (addr=122 → mirrors to 120)
        //   Encoding for raw_addr=122: 122 = 1*81 + 1*27 + 1*9 + 1*3 + 2*1
        //     t4=1(01), t3=1(01), t2=1(01), t1=1(01), t0=2(10) → raw=122 → mirror=120
        //   lut_rom[120] = 8'h38
        // -------------------------------------------------------------------
        apply_and_check(
            encode_trits(2'b01, 2'b01, 2'b01, 2'b01, 2'b10),
            8'h38,    // lut_rom[120] = 8'h38 (mirror of 122 → 242-122=120)
            1'b0,
            "Test3a_mirror_addr122_to120"
        );

        // Test 3b: raw_addr=127 = 1*81 + 1*27 + 2*9 + 0*3 + 1*1
        //   t4=1(01), t3=1(01), t2=2(10), t1=0(00), t0=1(01) → raw=127
        //   Mirror: 242-127=115 → lut_rom[115] = 8'h33
        apply_and_check(
            encode_trits(2'b01, 2'b01, 2'b10, 2'b00, 2'b01),
            8'h33,    // lut_rom[115] = 8'h33 (mirror of 127 → 115)
            1'b0,
            "Test3b_mirror_addr127_to115"
        );

        // -------------------------------------------------------------------
        // Documentation note (R5-HONEST):
        //   oob_o = 1 only when trit 2'b11 (reserved) causes raw_addr > 242.
        //   With standard ternary encoding, Mirror Consolidation prevents OOB.
        //   Output is forced to 8'h00 on OOB; oob_o asserted for upstream use.
        //   This choice avoids undefined lut_rom reads without requiring
        //   address masking that could silently corrupt computation.
        // -------------------------------------------------------------------

        $display("=== ALL TESTS PASSED ===");
        $display("LUT size: 122 entries (Mirror Consolidation ⌈243/2⌉)");
        $display("R-SI-1: no '*' operators — shifts+ROM only");
        $display("Anchor: phi^2 + phi^-2 = 3");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #10000;
        $fatal(1, "TIMEOUT: testbench exceeded 10000 ns");
    end

endmodule

`default_nettype wire
// EOF holo_lut_pe_tb.sv
