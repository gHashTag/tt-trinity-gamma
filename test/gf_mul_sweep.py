#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Value-domain sweep for the larger gfN_mul units (gf20/24/32/64/128), where an
# exhaustive sweep is infeasible. For each rung it feeds several thousand
# finite-normal (a,b) pairs (chosen so the product stays a finite normal) through
# iverilog and compares each result, in ULPs, to an exact-rational reference
# (decode -> Fraction -> multiply). Exact rationals are used because gf64/gf128
# values overflow IEEE double. Exit 0 iff every rung is within tolerance.
#
# This complements test/gf_arith_xcheck.py (which probes only mantissa==0): the
# sweep exercises the mantissa product and the guard/round/sticky rounding path.
import os, subprocess, sys, tempfile
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")
TOL_ULP = Fraction(1, 2)        # round-to-nearest ties-to-zero: <= 0.5 ULP

RUNGS = {  # name: (total, E, M)
    "gf6": (6, 2, 3), "gf10": (10, 3, 6), "gf14": (14, 5, 8),
    "gf48": (48, 18, 29), "gf96": (96, 36, 59),
    "gf12": (12, 4, 7),
    "gf20": (20, 7, 12), "gf24": (24, 9, 14), "gf32": (32, 12, 19),
    "gf64": (64, 24, 39), "gf128": (128, 49, 78), "gf256": (256, 97, 158),
}

def bias(E):    return 2 ** (E - 1) - 1
def expmax(E):  return 2 ** E - 1

def decode(code, E, M):
    s = (code >> (E + M)) & 1
    e = (code >> M) & (2 ** E - 1)
    m = code & (2 ** M - 1)
    sign = -1 if s else 1
    if e == 0 and m == 0:        return ("zero",)
    if e == expmax(E):           return ("special",)
    # value = sign * (2^M + m) * 2^(e - bias - M)   -- exact
    return ("num", Fraction(sign * (2 ** M + m)) * Fraction(2) ** (e - bias(E) - M))

def flog2(x):                    # floor(log2(positive Fraction))
    n, d = x.numerator, x.denominator
    e = n.bit_length() - d.bit_length()
    return e if (Fraction(2) ** e <= x) else e - 1

def mant_samples(M):
    top = 2 ** M
    base = [0, 1, 2, 3, top - 1, top - 2, top // 2, top // 2 + 1]
    base += [top // 3, top // 7, (5 * top) // 8, (top * 11) // 16 + 1]
    return sorted(set(v % top for v in base))

def gen_pairs(E, M):
    b = bias(E); pairs = []
    MS = mant_samples(M)
    for da in range(-2, 3):
        for db in range(-2, 3):
            # clamp to valid normal exponents [0, expmax-1] (tiny-bias formats
            # like gf6 (bias=1) would otherwise generate negative exponents)
            ea = max(0, min(expmax(E) - 1, b + da))
            eb = max(0, min(expmax(E) - 1, b + db))
            for ma in MS:
                for mb in MS:
                    for sa, sb in ((0, 0), (1, 0)):
                        a = (sa << (E + M)) | (ea << M) | ma
                        bb = (sb << (E + M)) | (eb << M) | mb
                        pairs.append((a, bb))
    return pairs

TB = """`timescale 1ns/1ps
module tb;
  reg [{hi}:0] av [0:{nm1}];
  reg [{hi}:0] bv [0:{nm1}];
  reg [{hi}:0] x, y; wire [{hi}:0] p;
  {name}_mul u(.a(x), .b(y), .result(p));
  integer i;
  initial begin
    $readmemh("{af}", av);
    $readmemh("{bf}", bv);
    for (i = 0; i < {n}; i = i + 1) begin
      x = av[i]; y = bv[i]; #1; $display("R %h", p);
    end
    $finish;
  end
endmodule
"""

SAFE_EXP = 4096

def is_overflow(atrue, E, M):
    oexp = expmax(E) - bias(E)
    if oexp <= SAFE_EXP:
        # IEEE round-to-nearest overflow threshold (1 - 2^-(M+2)) * 2^oexp
        return atrue >= Fraction(2**(M+2) - 1, 2**(M+2)) * Fraction(2) ** oexp
    return flog2(atrue) >= oexp

def is_underflow(atrue, E, M):
    b = bias(E)
    if b <= SAFE_EXP:
        return atrue < Fraction(2 ** M + 1, 2 ** M) * Fraction(1, 1 << b)
    return flog2(atrue) < -b

def run_rung(name):
    total, E, M = RUNGS[name]
    pairs = gen_pairs(E, M)
    n = len(pairs)
    with tempfile.TemporaryDirectory() as d:
        af, bf = os.path.join(d, "a.hex"), os.path.join(d, "b.hex")
        with open(af, "w") as fa, open(bf, "w") as fb:
            fa.write("\n".join("%x" % a for a, _ in pairs))
            fb.write("\n".join("%x" % b for _, b in pairs))
        tbp, outp = os.path.join(d, "tb.v"), os.path.join(d, "sim")
        with open(tbp, "w") as f:
            f.write(TB.format(hi=total - 1, nm1=n - 1, n=n, name=name, af=af, bf=bf))
        c = subprocess.run(["iverilog", "-g2012", "-o", outp,
                            os.path.join(SRC, name + "_mul.v"), tbp],
                           capture_output=True, text=True)
        if c.returncode != 0:
            print(f"  {name}: iverilog FAILED\n{c.stderr}"); return None
        r = subprocess.run(["vvp", outp], capture_output=True, text=True)
        outs = [l.split()[1] for l in r.stdout.splitlines() if l.startswith("R ")]
    if len(outs) != n:
        print(f"  {name}: expected {n} outputs, got {len(outs)}"); return None

    worst = Fraction(0); bad = []
    for (a, b), hexout in zip(pairs, outs):
        da_, db_ = decode(a, E, M), decode(b, E, M)
        if da_[0] != "num" or db_[0] != "num":
            continue                                    # skip special/zero inputs
        if "x" in hexout.lower() or "z" in hexout.lower():
            bad.append((a, b, hexout, "X/Z on num inputs")); continue
        out = int(hexout, 16); do = decode(out, E, M)
        true = da_[1] * db_[1]
        if true == 0:
            continue
        atrue = abs(true)
        # at the over/underflow boundary, flush vs round-to-min/max-normal are both
        # within 1 ULP -> accept either (reduced formats differ on the exact edge).
        if is_overflow(atrue, E, M):
            vmax = Fraction(2**(M+1) - 1, 2**M) * Fraction(2) ** (expmax(E) - 1 - bias(E))
            if not (do[0] == "special" or (do[0] == "num" and abs(do[1]) >= vmax * Fraction(1023,1024))):
                bad.append((a, b, out, "overflow boundary"))
            continue
        if is_underflow(atrue, E, M):
            vmin = Fraction(2**M + 1, 2**M) * Fraction(1, 1 << bias(E))
            if not (do[0] == "zero" or (do[0] == "num" and abs(do[1]) <= vmin)):
                bad.append((a, b, out, "underflow boundary"))
            continue
        if do[0] != "num":
            bad.append((a, b, out, "non-num")); continue
        if (do[1] < 0) != (true < 0):
            bad.append((a, b, out, "sign")); continue
        ulp = Fraction(2) ** (flog2(atrue) - M)
        err = abs(do[1] - true) / ulp
        if err > worst: worst = err
        if err > TOL_ULP:
            bad.append((a, b, out, "%.3f ULP" % float(err)))
    return n, worst, bad

def main():
    all_ok = True
    print("gfN_mul value sweep (exact-rational reference, tol 0.5 ULP):")
    for name in RUNGS:
        res = run_rung(name)
        if res is None:
            all_ok = False; continue
        n, worst, bad = res
        status = "PASS" if not bad else "FAIL (%d bad)" % len(bad)
        print(f"  {name}: {n} pairs, max {float(worst):.4f} ULP -> {status}")
        for (a, b, o, why) in bad[:4]:
            print(f"      {a:x} * {b:x} -> {(o if isinstance(o,str) else format(o,'x'))}  ({why})")
        if bad:
            all_ok = False
    print("RESULT:", "ALL PASS" if all_ok else "FAIL")
    return 0 if all_ok else 1

if __name__ == "__main__":
    sys.exit(main())
