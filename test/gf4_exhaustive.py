#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Exhaustive cross-check of gf4_add / gf4_mul over all 256 (a,b) input pairs.
# GF4 is degenerate (bias 0): the finite set is {+-0,+-1.25,+-1.5,+-1.75,+-Inf,NaN}
# (the significand 4+mant in quarter units; e0m0 is zero so 1.0 is unrepresentable).
# The reference decodes each operand exactly, applies the op, and rounds to nearest
# of that grid (spacing 0.25, overflow above 1.875). The generic exponent probe
# cannot test gf4 (its "1.0=exp=bias" collides with the zero code), so this is the
# authoritative gf4 check. Exit 0 iff all 256 pairs match for both ops.
import os, subprocess, sys, tempfile
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")

GRID = [Fraction(5, 4), Fraction(6, 4), Fraction(7, 4)]   # 1.25, 1.5, 1.75
OVERFLOW = Fraction(15, 8)                                 # 1.875 = 1.75 + 0.5 ULP

def decode(code):
    s, e, m = (code >> 3) & 1, (code >> 2) & 1, code & 3
    if e == 0 and m == 0: return ("zero",)
    if e == 1 and m == 0: return ("inf", s)
    if e == 1:            return ("nan",)
    return ("num", (-1 if s else 1) * Fraction(4 + m, 4))

def encode(true):
    """Round an exact value to the nearest gf4 code (ties away from zero)."""
    if true == 0:
        return 0x0
    neg = true < 0
    v = -true if neg else true
    if v >= OVERFLOW:
        return 0xC if neg else 0x4
    # nearest of {0} U GRID
    best, bestd = 0, v                       # distance to zero
    for g, m in zip(GRID, (1, 2, 3)):
        d = abs(v - g)
        if d < bestd or (d == bestd and best != 0):   # ties away from zero
            best, bestd = m, d
    if best == 0:
        return 0x8 if neg else 0x0
    return (0x8 if neg else 0) | best

def ref(op, a, b):
    da, db = decode(a), decode(b)
    if da[0] == "nan" or db[0] == "nan": return ("nan",)
    if op == "mul":
        if (da[0] == "zero" and db[0] == "inf") or (da[0] == "inf" and db[0] == "zero"):
            return ("nan",)
        sgn = ((a >> 3) ^ (b >> 3)) & 1
        if da[0] == "inf" or db[0] == "inf": return ("inf", sgn)
        if da[0] == "zero" or db[0] == "zero": return ("zerosign", sgn)
        return ("code", encode(da[1] * db[1]))
    else:
        if da[0] == "inf" and db[0] == "inf":
            return ("nan",) if da[1] != db[1] else ("inf", da[1])
        if da[0] == "inf": return ("inf", da[1])
        if db[0] == "inf": return ("inf", db[1])
        if da[0] == "zero" and db[0] == "zero": return ("code", 0x0)
        if da[0] == "zero": return ("code", b)
        if db[0] == "zero": return ("code", a)
        return ("code", encode(da[1] + db[1]))

def ok(op, a, b, out):
    r = ref(op, a, b)
    do = decode(out)
    if r[0] == "nan":      return do[0] == "nan"
    if r[0] == "inf":      return do[0] == "inf" and ((out >> 3) & 1) == r[1]
    if r[0] == "zerosign": return do[0] == "zero"           # +/-0 both fine
    return out == r[1]                                      # exact code match

TB = """`timescale 1ns/1ps
module tb;
  reg [3:0] a, b; wire [3:0] s, p;
  gf4_add ua(.a(a), .b(b), .result(s));
  gf4_mul um(.a(a), .b(b), .result(p));
  integer i, j;
  initial begin
    for (i = 0; i < 16; i = i + 1)
      for (j = 0; j < 16; j = j + 1) begin
        a = i[3:0]; b = j[3:0]; #1; $display("R %h %h %h %h", a, b, s, p);
      end
    $finish;
  end
endmodule
"""

def main():
    with tempfile.TemporaryDirectory() as d:
        tbp, outp = os.path.join(d, "tb.v"), os.path.join(d, "sim")
        open(tbp, "w").write(TB)
        c = subprocess.run(["iverilog", "-g2012", "-o", outp,
                            os.path.join(SRC, "gf4_add.v"),
                            os.path.join(SRC, "gf4_mul.v"), tbp],
                           capture_output=True, text=True)
        if c.returncode != 0:
            print("iverilog FAILED:\n" + c.stderr); return 2
        r = subprocess.run(["vvp", outp], capture_output=True, text=True)
        rows = [l.split()[1:] for l in r.stdout.splitlines() if l.startswith("R ")]
    add_bad, mul_bad, n = [], [], 0
    for a, b, s, p in [tuple(int(x, 16) for x in row) for row in rows]:
        n += 1
        if not ok("add", a, b, s): add_bad.append((a, b, s))
        if not ok("mul", a, b, p): mul_bad.append((a, b, p))
    print(f"gf4 exhaustive cross-check: {n} pairs")
    print(f"  add: {n - len(add_bad)}/{n} pass")
    print(f"  mul: {n - len(mul_bad)}/{n} pass")
    for name, bad in (("add", add_bad), ("mul", mul_bad)):
        for (a, b, o) in bad[:6]:
            print(f"  FAIL {name} {a:x} {b:x} -> {o:x}  (ref {ref(name, a, b)})")
    good = not add_bad and not mul_bad
    print("RESULT:", "ALL PASS" if good else "FAIL")
    return 0 if good else 1

if __name__ == "__main__":
    sys.exit(main())
