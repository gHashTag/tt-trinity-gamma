// SPDX-License-Identifier: Apache-2.0
// tt-trinity-gamma/test/gfternary_tf3_tb.v
// Self-checking testbench for the two GoldenFloat rungs that previously had no
// RTL: GFTernary (2-bit) and TF3 (8-bit). Decode is checked against golden
// vectors derived from the canonical formulas; the GFTernary encoder is checked
// round-trip. Run: iverilog -g2012 -o /tmp/x ../src/gfternary_to_fp32.v \
//   ../src/tf3_to_fp32.v gfternary_tf3_tb.v && vvp /tmp/x
`timescale 1ns/1ps

module gfternary_tf3_tb;
    integer errors = 0;

    // --- GFTernary decode -------------------------------------------------
    reg  [1:0]  g;  wire [31:0] gfp;
    gfternary_to_fp32 u_gd (.gft_in(g), .fp_out(gfp));
    task chk_g(input [1:0] code, input [31:0] exp);
        begin g = code; #1;
            if (gfp !== exp) begin
                $display("FAIL GFTernary %b: got %08h exp %08h", code, gfp, exp);
                errors = errors + 1;
            end
        end
    endtask

    // --- GFTernary encode (round-trip / thresholds) -----------------------
    reg  [31:0] x;  wire [1:0] gc;
    fp32_to_gfternary u_ge (.fp_in(x), .gft_out(gc));
    task chk_e(input [31:0] val, input [1:0] exp);
        begin x = val; #1;
            if (gc !== exp) begin
                $display("FAIL encode %08h: got %b exp %b", val, gc, exp);
                errors = errors + 1;
            end
        end
    endtask

    // --- TF3 decode -------------------------------------------------------
    reg  [7:0]  t;  wire [31:0] tfp;
    tf3_to_fp32 u_t (.tf3_in(t), .fp_out(tfp));
    task chk_t(input [7:0] code, input [31:0] exp);
        begin t = code; #1;
            if (tfp !== exp) begin
                $display("FAIL TF3 %02h: got %08h exp %08h", code, tfp, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // GFTernary decode: {0, +phi, -phi, reserved->qNaN}
        chk_g(2'b00, 32'h00000000);
        chk_g(2'b01, 32'h3FCF1BBD);   // +phi
        chk_g(2'b10, 32'hBFCF1BBD);   // -phi
        chk_g(2'b11, 32'h7FC00000);   // reserved

        // GFTernary encode: nearest of {0,+phi,-phi}; boundary phi/2; NaN/Inf->11
        chk_e(32'h00000000, 2'b00);   // 0
        chk_e(32'h3FCF1BBD, 2'b01);   // +phi
        chk_e(32'hBFCF1BBD, 2'b10);   // -phi
        chk_e(32'h3F000000, 2'b00);   // 0.5  (< phi/2)
        chk_e(32'h3F800000, 2'b01);   // 1.0  (> phi/2)
        chk_e(32'hBF800000, 2'b10);   // -1.0
        chk_e(32'h7FC00000, 2'b11);   // NaN
        chk_e(32'h7F800000, 2'b11);   // +Inf

        // TF3 decode: (-1)^S (1 + M/16) 2^(E-3); specials below.
        chk_t(8'h00, 32'h00000000);   // +0
        chk_t(8'h80, 32'h80000000);   // -0
        chk_t(8'h30, 32'h3F800000);   // e3 m0 = 1.0
        chk_t(8'hB0, 32'hBF800000);   // -1.0
        chk_t(8'h48, 32'h40400000);   // e4 m8 = 3.0
        chk_t(8'h0F, 32'h3E780000);   // e0 m15 = 0.2421875
        chk_t(8'h67, 32'h41380000);   // e6 m7 = 11.5
        // NB: true Inf is exp=7,mant=0 -> 0x70/0xF0. The spec's named
        // TF3_INF_POS=0x78 is exp=7,mant=8 (i.e. NaN); this RTL follows the
        // bit layout, which is self-consistent.
        chk_t(8'h70, 32'h7F800000);   // +Inf
        chk_t(8'hF0, 32'hFF800000);   // -Inf
        chk_t(8'h79, 32'h7FC00000);   // e7 m1 = NaN
        chk_t(8'h78, 32'h7FC00000);   // 0x78 (spec "INF") is actually NaN

        if (errors == 0)
            $display("ALL PASS: GFTernary + TF3 decode/encode (golden vectors)");
        else
            $display("FAIL: %0d mismatch(es)", errors);
        $finish;
    end
endmodule
