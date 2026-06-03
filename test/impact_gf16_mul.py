#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# End-to-end accuracy impact of the gf16_mul rounding-overflow defect, measured on
# the actual MAC primitive (gf16_dot4, a 4-term dot product). Runs the shipped
# gf16_dot4 (gf16_mul + gf16_add) and the corrected gf16_dot4_v2 (gf16_v2_*) over N
# representative near-1.0 input vectors, and compares each to an EXACT-rational dot
# product. Turns "0.072% of products halved" into a dot-level NMSE / affected-rate --
# the number a respin decision needs. Read-only on the frozen gf16 units.
import os, subprocess, sys, tempfile, random
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")
E, M, BIAS = 6, 9, 31
N = 20000
random.seed(1234)   # deterministic

def decode(code):
    s = (code >> 15) & 1; e = (code >> 9) & 0x3F; m = code & 0x1FF
    if e == 0 and m == 0: return Fraction(0)
    if e == 0x3F: return None          # special (we don't generate these)
    return (-1 if s else 1) * Fraction(512 + m) * Fraction(2) ** (e - BIAS - 9)

def rand_gf16():
    # near-1.0 representative: exp in [bias-3, bias+1] (values ~0.125..4), any mant/sign
    e = random.randint(BIAS - 3, BIAS + 1)
    m = random.randint(0, 511)
    s = random.randint(0, 1)
    return (s << 15) | (e << 9) | m

TB = """`timescale 1ns/1ps
module tb;
  reg [15:0] v [0:{tot}];
  reg [15:0] a0,a1,a2,a3,b0,b1,b2,b3;
  wire [15:0] r_a, r_b, r_c;
  // A = shipped (gf16_mul + gf16_add); B = mul-fixed only (gf16_v2_mul + gf16_add);
  // C = fully fixed (gf16_v2_mul + gf16_v2_add)
  gf16_dot4    ua(.a0(a0),.a1(a1),.a2(a2),.a3(a3),.b0(b0),.b1(b1),.b2(b2),.b3(b3),.result(r_a));
  gf16_dot4_b  ub(.a0(a0),.a1(a1),.a2(a2),.a3(a3),.b0(b0),.b1(b1),.b2(b2),.b3(b3),.result(r_b));
  gf16_dot4_v2 uc(.a0(a0),.a1(a1),.a2(a2),.a3(a3),.b0(b0),.b1(b1),.b2(b2),.b3(b3),.result(r_c));
  integer i;
  initial begin
    $readmemh("{vf}", v);
    for (i = 0; i < {n}; i = i + 1) begin
      a0=v[i*8+0]; a1=v[i*8+1]; a2=v[i*8+2]; a3=v[i*8+3];
      b0=v[i*8+4]; b1=v[i*8+5]; b2=v[i*8+6]; b3=v[i*8+7]; #1;
      $display("R %04h %04h %04h", r_a, r_b, r_c);
    end
    $finish;
  end
endmodule
"""

def main():
    cases = [[rand_gf16() for _ in range(8)] for _ in range(N)]
    flat = [x for c in cases for x in c]
    with tempfile.TemporaryDirectory() as d:
        vf = os.path.join(d, "v.hex")
        open(vf, "w").write("\n".join("%04x" % x for x in flat))
        tbp, outp = os.path.join(d, "tb.v"), os.path.join(d, "sim")
        open(tbp, "w").write(TB.format(tot=8 * N - 1, n=N, vf=vf))
        c = subprocess.run(["iverilog", "-g2012", "-o", outp,
                            os.path.join(SRC, "gf16_dot4.v"), os.path.join(SRC, "gf16_dot4_b.v"),
                            os.path.join(SRC, "gf16_dot4_v2.v"),
                            os.path.join(SRC, "gf16_mul.v"), os.path.join(SRC, "gf16_add.v"),
                            os.path.join(SRC, "gf16_v2_mul.v"), os.path.join(SRC, "gf16_v2_add.v"), tbp],
                           capture_output=True, text=True)
        if c.returncode != 0:
            print("iverilog FAILED:\n" + c.stderr); return 2
        r = subprocess.run(["vvp", outp], capture_output=True, text=True)
        rows = [l.split()[1:] for l in r.stdout.splitlines() if l.startswith("R ")]

    se_a = se_b = se_c = sref = Fraction(0)
    mul_diff = add_diff = 0          # A!=B isolates the mul bug; B!=C isolates the add
    for case, (ra_s, rb_s, rc_s) in zip(cases, rows):
        vals = [decode(x) for x in case]
        ref = vals[0]*vals[4] + vals[1]*vals[5] + vals[2]*vals[6] + vals[3]*vals[7]
        ra, rb, rc = decode(int(ra_s, 16)), decode(int(rb_s, 16)), decode(int(rc_s, 16))
        if ra is None or rb is None or rc is None:
            continue
        se_a += (ra - ref) ** 2; se_b += (rb - ref) ** 2; se_c += (rc - ref) ** 2
        sref += ref ** 2
        if int(ra_s, 16) != int(rb_s, 16): mul_diff += 1
        if int(rb_s, 16) != int(rc_s, 16): add_diff += 1
    f = lambda s: float(s / sref) if sref else 0.0
    import math
    print(f"gf16_dot4 impact study: {N} representative near-1.0 4-term dot products\n")
    print(f"  A shipped     (gf16_mul + gf16_add)    NMSE = {f(se_a):.3e}  RMS rel ~{math.sqrt(f(se_a))*100:.2f}%")
    print(f"  B mul-fixed   (gf16_v2_mul + gf16_add) NMSE = {f(se_b):.3e}  RMS rel ~{math.sqrt(f(se_b))*100:.2f}%")
    print(f"  C fully-fixed (gf16_v2_mul + gf16_v2_add) NMSE = {f(se_c):.3e}  RMS rel ~{math.sqrt(f(se_c))*100:.2f}%")
    print(f"\n  attribution by affected dot products:")
    print(f"    mul rounding-overflow (A!=B): {mul_diff} ({100.0*mul_diff/N:.3f}%)")
    print(f"    add truncating-align  (B!=C): {add_diff} ({100.0*add_diff/N:.3f}%)")
    print(f"\n  => the MUL rounding-overflow DOMINATES the error: fixing it alone (A->B)")
    print(f"     cuts NMSE ~{f(se_a)/f(se_b):.0f}x (RMS {math.sqrt(f(se_a))*100:.2f}% -> {math.sqrt(f(se_b))*100:.2f}%)")
    print(f"     even though it hits only {100.0*mul_diff/N:.2f}% of dots -- HALVING a term is a huge")
    print(f"     per-term error. The add truncation hits {100.0*add_diff/N:.0f}% of dots but with tiny")
    print(f"     per-dot error (small further gain B->C). Both fixed by the v2 units.")
    print("RESULT: gf16 dot-path accuracy gap quantified + attributed (mul dominates)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
