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

    // --- TF3 encode (FP32 -> TF3, round-to-nearest) -----------------------
    reg  [31:0] tx;  wire [7:0] tc;
    fp32_to_tf3 u_te (.fp_in(tx), .tf3_out(tc));
    task chk_te(input [31:0] val, input [7:0] exp);
        begin tx = val; #1;
            if (tc !== exp) begin
                $display("FAIL TF3-enc %08h: got %02h exp %02h", val, tc, exp);
                errors = errors + 1;
            end
        end
    endtask

    // --- TF3 round-trip: encode(decode(b)) == b for all finite/Inf codes ---
    reg  [7:0]  rb;  wire [31:0] rfp;  wire [7:0] rb2;
    tf3_to_fp32 u_rd (.tf3_in(rb), .fp_out(rfp));
    fp32_to_tf3 u_re (.fp_in(rfp), .tf3_out(rb2));
    integer k;

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

        // TF3 encode golden (round-to-nearest)
        chk_te(32'h00000000, 8'h00);  // +0
        chk_te(32'h80000000, 8'h80);  // -0
        chk_te(32'h3F800000, 8'h30);  // 1.0  -> e3 m0
        chk_te(32'h40400000, 8'h48);  // 3.0  -> e4 m8
        chk_te(32'h3F000000, 8'h20);  // 0.5  -> e2 m0
        chk_te(32'h41700000, 8'h6E);  // 15.0 -> e6 m14
        chk_te(32'h42C80000, 8'h6F);  // 100  -> saturate max finite
        chk_te(32'hC0400000, 8'hC8);  // -3.0
        chk_te(32'h7F800000, 8'h70);  // +Inf
        chk_te(32'hFF800000, 8'hF0);  // -Inf

        // TF3 round-trip: encode(decode(b)) == b for all finite/Inf codes
        // (E==7,M!=0 are NaN; their payload canonicalizes, so skip).
        for (k = 0; k < 256; k = k + 1) begin
            rb = k[7:0]; #1;
            if (!(rb[6:4] == 3'b111 && rb[3:0] != 4'd0)) begin
                if (rb2 !== rb) begin
                    $display("FAIL TF3 round-trip %02h -> %02h", rb, rb2);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0)
            $display("ALL PASS: GFTernary + TF3 decode/encode + round-trip");
        else
            $display("FAIL: %0d mismatch(es)", errors);
        $finish;
    end
endmodule
