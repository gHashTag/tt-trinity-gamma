`timescale 1ns/1ps
// posit16_gate.v — self-contained CI check for the posit16 codec (no external reference).
//
// Invariant: in posit16's "golden band" the format carries >=10 fraction bits, so any
// fp16 normal there survives fp16 -> posit16 -> fp16 EXACTLY (lossless round-trip).
// posit16 es=2: magnitude(15) = regime_len + 2(exp) + frac, frac >= 10 needs regime_len <=3,
// i.e. scale exponent in [-8,7] -> fp16 exp16 in [7,22]. Sweep all mantissas, both signs.
module posit16_gate;
  reg  signed [15:0] fp16_in;
  wire [15:0] posit_q;
  reg  [15:0] posit_drive;
  wire signed [15:0] fp16_rt;

  posit16_quantizer   QU(.fp16_in(fp16_in), .posit16_out(posit_q));
  posit16_dequantizer DQ(.posit16_in(posit_drive), .fp16_out(fp16_rt));

  integer e, m, s, fails;
  reg [15:0] h;
  initial begin
    fails=0;
    for (s=0;s<2;s=s+1)
      for (e=7;e<=22;e=e+1)
        for (m=0;m<1024;m=m+1) begin
          h = {s[0], e[4:0], m[9:0]};
          fp16_in = h; #1;
          posit_drive = posit_q; #1;
          if (fp16_rt !== h) begin
            fails=fails+1;
            if (fails<=8) $display("  POSIT16 GATE FAIL: in=%04x q=%04x rt=%04x", h, posit_q, fp16_rt);
          end
        end
    if (fails==0) $display("POSIT16 GATE: 0 fail -> CLEAN (lossless golden-band round-trip)");
    else          $display("POSIT16 GATE: %0d FAIL", fails);
    $finish;
  end
endmodule
