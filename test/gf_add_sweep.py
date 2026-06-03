#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Value-domain sweep for gfN_add units. For each rung it feeds several thousand
# finite-normal (a,b) pairs (both sign combinations, so add AND subtract, plus
# wide exponent gaps to exercise alignment + sticky) through iverilog and compares
# each result, in ULPs, to an exact-rational reference (decode -> Fraction -> add).
#
# gf8 (exhaustively verified elsewhere) is included as a methodology check.
# NB: gf16_add -- the [Verified] reference rung -- does NOT pass this sweep (it
# uses a truncating alignment and is up to ~512 ULP off on subtractive
# cancellation, e.g. 0.5009765625 + (-1.0) yields -0.5 not the exact -0.4990234375
# = 0xbbfe). That is a real legacy-imprecision finding (see docs/GF_ARITH_FINDINGS
# .md); gf16 is silicon-validated so it is left untouched here. The fixed gf8/gf12
# add units use guard/round/sticky and stay < 1 ULP. Exit 0 iff every listed rung
# is within tolerance.
import os, subprocess, sys, tempfile
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")
TOL_ULP = Fraction(1)            # faithful rounding (G=3 guard bits -> <1 ULP)

RUNGS = {  # name: (total, E, M)  -- all the regenerated (GRS) add units
    "gf8": (8, 3, 4), "gf12": (12, 4, 7), "gf20": (20, 7, 12),
    "gf24": (24, 9, 14), "gf32": (32, 12, 19), "gf64": (64, 24, 39),
    "gf128": (128, 48, 79),
}

def bias(E):   return 2 ** (E - 1) - 1
def emax(E):   return 2 ** E - 1

def decode(code, E, M):
    s = (code >> (E + M)) & 1
    e = (code >> M) & (2 ** E - 1)
    m = code & (2 ** M - 1)
    sign = -1 if s else 1
    if e == 0 and m == 0:  return ("zero",)
    if e == emax(E):       return ("special",)
    return ("num", Fraction(sign * (2 ** M + m)) * Fraction(2) ** (e - bias(E) - M))

def flog2(x):
    n, d = x.numerator, x.denominator
    e = n.bit_length() - d.bit_length()
    return e if (Fraction(2) ** e <= x) else e - 1

# NB: the overflow/underflow bounds are 2^(2^(E-1)) and 2^(-bias) -- for the large
# rungs (gf64/gf128) these are multi-million-digit integers, so materialize them
# only when the exponent is small (<= SAFE_EXP). For the large rungs the mid-range
# sweep never reaches those regions, so a coarse flog2 comparison is exact enough.
SAFE_EXP = 4096

def is_overflow(atrue, E, M):
    oexp = emax(E) - bias(E)                            # = 2^(E-1)
    if oexp <= SAFE_EXP:
        return atrue >= Fraction(2) ** oexp
    return flog2(atrue) >= oexp

def is_underflow(atrue, E, M):
    b = bias(E)
    if b <= SAFE_EXP:
        return atrue < Fraction(2 ** M + 1, 2 ** M) * Fraction(1, 1 << b)
    return flog2(atrue) < -b

def mant_samples(M):
    top = 2 ** M
    return sorted(set(v % top for v in
        [0, 1, 2, top - 1, top - 2, top // 2, top // 3, (3 * top) // 4 + 1]))

def gen_pairs(E, M):
    b = bias(E); MS = mant_samples(M); pairs = []
    offs = [-1, 0, 1]
    for da in offs:
        for db in offs:
            for ma in MS:
                for mb in MS:
                    for sa, sb in ((0, 0), (0, 1), (1, 0), (1, 1)):
                        a = (sa << (E + M)) | ((b + da) << M) | ma
                        bb = (sb << (E + M)) | ((b + db) << M) | mb
                        pairs.append((a, bb))
    # wide-gap pairs to exercise alignment + sticky
    for dg in range(2, min(M + 2, emax(E) - 1 - b)):
        for ma in MS[:4]:
            for mb in MS[:4]:
                for sa, sb in ((0, 0), (1, 0)):
                    a = (sa << (E + M)) | ((b) << M) | ma
                    bb = (sb << (E + M)) | ((b - dg) << M) | mb
                    pairs.append((a, bb))
    return pairs

TB = """`timescale 1ns/1ps
module tb;
  reg [{hi}:0] av [0:{nm1}];
  reg [{hi}:0] bv [0:{nm1}];
  reg [{hi}:0] x, y; wire [{hi}:0] p;
  {name}_add u(.a(x), .b(y), .result(p));
  integer i;
  initial begin
    $readmemh("{af}", av); $readmemh("{bf}", bv);
    for (i = 0; i < {n}; i = i + 1) begin
      x = av[i]; y = bv[i]; #1; $display("R %h", p);
    end
    $finish;
  end
endmodule
"""

def check(true, out, E, M):
    do = decode(out, E, M)
    atrue = abs(true)
    if true == 0:
        return do[0] == "zero", Fraction(0)
    le = flog2(atrue)
    if is_overflow(atrue, E, M):
        return do[0] == "special", Fraction(0)   # overflow -> Inf/NaN region
    if is_underflow(atrue, E, M):
        return do[0] == "zero" or do[0] == "num", Fraction(0)  # underflow boundary
    if do[0] != "num":
        return False, Fraction(10 ** 9)
    if (do[1] < 0) != (true < 0):
        return False, Fraction(10 ** 9)
    ulp = Fraction(2) ** (le - M)
    return abs(do[1] - true) <= ulp * TOL_ULP, abs(do[1] - true) / ulp

def run_rung(name):
    total, E, M = RUNGS[name]
    pairs = gen_pairs(E, M); n = len(pairs)
    with tempfile.TemporaryDirectory() as d:
        af, bf = os.path.join(d, "a.hex"), os.path.join(d, "b.hex")
        open(af, "w").write("\n".join("%x" % a for a, _ in pairs))
        open(bf, "w").write("\n".join("%x" % b for _, b in pairs))
        tbp, outp = os.path.join(d, "tb.v"), os.path.join(d, "sim")
        open(tbp, "w").write(TB.format(hi=total - 1, nm1=n - 1, n=n, name=name, af=af, bf=bf))
        c = subprocess.run(["iverilog", "-g2012", "-o", outp,
                            os.path.join(SRC, name + "_add.v"), tbp],
                           capture_output=True, text=True)
        if c.returncode != 0:
            print(f"  {name}: iverilog FAILED\n{c.stderr}"); return None
        r = subprocess.run(["vvp", outp], capture_output=True, text=True)
        outs = [l.split()[1] for l in r.stdout.splitlines() if l.startswith("R ")]
    if len(outs) != n:
        print(f"  {name}: expected {n}, got {len(outs)}"); return None
    worst = Fraction(0); bad = []
    for (a, b), hexout in zip(pairs, outs):
        da_, db_ = decode(a, E, M), decode(b, E, M)
        if da_[0] != "num" or db_[0] != "num":
            continue
        true = da_[1] + db_[1]
        ok, err = check(true, int(hexout, 16), E, M)
        if err > worst and err < 10 ** 9:
            worst = err
        if not ok:
            bad.append((a, b, int(hexout, 16), "%.3f ULP" % float(err)))
    return n, worst, bad

def main():
    all_ok = True
    print("gfN_add value sweep (exact-rational reference, tol 1 ULP):")
    for name in RUNGS:
        res = run_rung(name)
        if res is None:
            all_ok = False; continue
        n, worst, bad = res
        status = "PASS" if not bad else "FAIL (%d bad)" % len(bad)
        print(f"  {name}: {n} pairs, max {float(worst):.4f} ULP -> {status}")
        for (a, b, o, why) in bad[:4]:
            print(f"      {a:x} + {b:x} -> {o:x}  ({why})")
        if bad:
            all_ok = False
    print("RESULT:", "ALL PASS" if all_ok else "FAIL")
    return 0 if all_ok else 1

if __name__ == "__main__":
    sys.exit(main())
