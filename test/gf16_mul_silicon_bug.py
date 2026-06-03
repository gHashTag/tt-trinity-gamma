#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Characterize the gf16_mul rounding-overflow bug (an ACTIVE silicon defect on the
# gf16 compute path of all three SKY26b dies). gf16_mul declares mant_rounded as
# [8:0] (M=9 bits), so `mant_out + 1` WRAPS when the mantissa is all-ones (0x1FF),
# and the overflow test `mant_rounded[9]` reads a nonexistent bit (always 0). When a
# product mantissa rounds up across a binade boundary, the exponent is NOT bumped ->
# the result is one binade too small (HALVED).
#
# This sweeps all 512x512 mantissa pairs at unit exponent (exp_a=exp_b=bias, the
# normalized-operand regime a MAC actually runs) and compares gf16_mul to the
# verified-correct gf16_v2_mul. Reports the defect RATE + an example. Read-only on
# the (frozen) gf16_mul; the fix is gf16_v2_mul.
import os, subprocess, sys, tempfile
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")
E, M, BIAS = 6, 9, 31

def decode(code):
    s = (code >> 15) & 1; e = (code >> 9) & 0x3F; m = code & 0x1FF
    if e == 0 and m == 0: return None
    if e == 0x3F: return None
    return (-1 if s else 1) * Fraction(512 + m) * Fraction(2) ** (e - BIAS - 9)

TB = """`timescale 1ns/1ps
module tb;
  reg [15:0] av [0:{nm1}]; reg [15:0] bv [0:{nm1}];
  reg [15:0] a, b; wire [15:0] po, pn;
  gf16_mul    uo(.a(a), .b(b), .result(po));
  gf16_v2_mul un(.a(a), .b(b), .result(pn));
  integer i;
  initial begin
    $readmemh("{af}", av); $readmemh("{bf}", bv);
    for (i = 0; i < {n}; i = i + 1) begin a = av[i]; b = bv[i]; #1;
      $display("R %04h %04h", po, pn); end
    $finish;
  end
endmodule
"""

def main():
    e = BIAS
    pairs = [(((e << 9) | ma), ((e << 9) | mb)) for ma in range(512) for mb in range(512)]
    n = len(pairs)
    with tempfile.TemporaryDirectory() as d:
        af, bf = os.path.join(d, "a.hex"), os.path.join(d, "b.hex")
        open(af, "w").write("\n".join("%04x" % a for a, _ in pairs))
        open(bf, "w").write("\n".join("%04x" % b for _, b in pairs))
        tbp, outp = os.path.join(d, "tb.v"), os.path.join(d, "sim")
        open(tbp, "w").write(TB.format(nm1=n - 1, n=n, af=af, bf=bf))
        c = subprocess.run(["iverilog", "-g2012", "-o", outp,
                            os.path.join(SRC, "gf16_mul.v"),
                            os.path.join(SRC, "gf16_v2_mul.v"), tbp],
                           capture_output=True, text=True)
        if c.returncode != 0:
            print("iverilog FAILED:\n" + c.stderr); return 2
        r = subprocess.run(["vvp", outp], capture_output=True, text=True)
        outs = [l.split()[1:] for l in r.stdout.splitlines() if l.startswith("R ")]

    diff = 0; halved = 0; examples = []
    for (a, b), (po_s, pn_s) in zip(pairs, [(x[0], x[1]) for x in outs]):
        po, pn = int(po_s, 16), int(pn_s, 16)
        if po == pn:
            continue
        diff += 1
        vo, vn = decode(po), decode(pn)
        if vo is not None and vn is not None and vn != 0 and vo == vn / 2:
            halved += 1
        if len(examples) < 4:
            examples.append((a, b, po, pn, float(vo) if vo else None, float(vn) if vn else None))
    print(f"gf16_mul vs gf16_v2_mul, all {n} mantissa pairs at unit exponent:")
    print(f"  differing results: {diff}  ({100.0*diff/n:.3f}% of products)")
    print(f"  of which exactly HALVED (binade-overflow bug): {halved}")
    for (a, b, po, pn, vo, vn) in examples:
        print(f"    a={a:04x} b={b:04x}: gf16_mul={po:04x} ({vo})  correct={pn:04x} ({vn})")
    # this is a report, not a pass/fail gate (the silicon is frozen)
    print("RESULT: active gf16_mul defect rate quantified (silicon frozen; fix = gf16_v2_mul)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
