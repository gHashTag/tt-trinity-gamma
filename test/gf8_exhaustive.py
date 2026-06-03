#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Exhaustive cross-check of gf8_add / gf8_mul over all 65536 (a,b) input pairs
# against an INDEPENDENT value-based reference (decode -> exact float -> op ->
# compare in ULPs). Non-circular: it does not replicate the RTL's bit slicing,
# it checks the produced numeric value. A correct unit lands within <=1 ULP of
# the true result (truncating-align rounding); the pre-fix RTL was off by whole
# factors (e.g. 1.0+1.0 -> 0.5, 2.0*1.0 -> 4.0), i.e. many ULPs / wrong special.
#
# Requires iverilog + vvp. Exit code 0 iff every pair passes.
import math, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")

# --- gf8 codec (layout [S|E3|M4], bias 3, no subnormals) --------------------
def decode(code):
    s = (code >> 7) & 1
    e = (code >> 4) & 7
    m = code & 0xF
    sign = -1.0 if s else 1.0
    if e == 0 and m == 0:
        return ("zero", s)
    if e == 7 and m == 0:
        return ("inf", s)
    if e == 7:
        return ("nan", 0)
    return ("num", sign * (1.0 + m / 16.0) * (2.0 ** (e - 3)))

MAX_FINITE  = (1.0 + 15.0 / 16.0) * (2.0 ** (6 - 3))  # e6 m15 = 15.5
OVERFLOW    = 2.0 ** 4                                 # 16.0: first value needing e7
MIN_NONZERO = (1.0 + 1.0 / 16.0) * (2.0 ** (0 - 3))   # e0 m1 = 0.1328125
# NB: e0m0 (0x00) is the ZERO encoding -- the value 0.125 is a representational
# hole, so the smallest nonzero magnitude is e0m1. Values in (0, MIN_NONZERO)
# flush toward zero. The truncating alignment (same convention as the verified
# gf16 units) costs up to ~2 ULP on subtractive cancellation / far-apart adds.
TOL_ULP = 1.0001   # faithful rounding: result within 1 ULP of the true value

def ulp_at(v):
    av = abs(v)
    E = math.floor(math.log2(av))          # unbiased binade exponent
    return 2.0 ** (E - 4)                  # adjacent-mantissa spacing

# --- reference op result, as a tag the RTL output must satisfy --------------
def ref(op, a, b):
    da, db = decode(a), decode(b)
    ta, tb = da[0], db[0]
    if ta == "nan" or tb == "nan":
        return ("nan",)
    if op == "mul":
        if (ta == "zero" and tb == "inf") or (ta == "inf" and tb == "zero"):
            return ("nan",)
        if ta == "inf" or tb == "inf":
            sgn = ((a >> 7) ^ (b >> 7)) & 1
            return ("inf", sgn)
        if ta == "zero" or tb == "zero":
            return ("zero", ((a >> 7) ^ (b >> 7)) & 1)
        true = da[1] * db[1]
    else:  # add
        if ta == "inf" and tb == "inf":
            return ("nan",) if da[1] != db[1] else ("inf", da[1])
        if ta == "inf":
            return ("inf", da[1])
        if tb == "inf":
            return ("inf", db[1])
        va = 0.0 if ta == "zero" else da[1]
        vb = 0.0 if tb == "zero" else db[1]
        true = va + vb
    if true == 0.0:
        return ("zero", None)              # sign of exact-zero result: accept either
    return ("num", true)

def check(op, a, b, out):
    """Return (ok, ulp_error). ulp_error is 0.0 for non-numeric verdicts."""
    r = ref(op, a, b)
    do = decode(out)
    kind = r[0]
    if kind == "nan":
        return do[0] == "nan", 0.0
    if kind == "inf":
        return (do[0] == "inf" and (out >> 7 & 1) == r[1]), 0.0
    if kind == "zero":
        return do[0] == "zero", 0.0        # +/-0 both accepted
    true = r[1]
    atrue = abs(true)
    want_neg = (1 if true < 0 else 0)
    # overflow: >= 16.0 must be Inf (would need e7).
    if atrue >= OVERFLOW:
        return (do[0] == "inf" and ((out >> 7) & 1) == want_neg), 0.0
    # round-to-nearest boundary [MAX_FINITE, 16): rounds to either max-finite or
    # Inf depending on round direction -- accept both.
    if atrue >= MAX_FINITE:
        if do[0] == "inf":
            return ((out >> 7) & 1) == want_neg, 0.0
        return (do[0] == "num" and (do[1] < 0) == (true < 0)
                and abs(do[1]) == MAX_FINITE), 0.0
    # underflow: (0, MIN_NONZERO) flushes toward zero (min-nonzero also accepted)
    if atrue < MIN_NONZERO:
        ok = do[0] == "zero" or (do[0] == "num" and abs(do[1]) == MIN_NONZERO)
        return ok, 0.0
    if do[0] != "num":
        return False, float("inf")
    if (do[1] < 0) != (true < 0):
        return False, float("inf")
    e = abs(do[1] - true) / ulp_at(true)
    return e <= TOL_ULP, e

# --- build the dump TB, run iverilog, parse ---------------------------------
TB = r"""
`timescale 1ns/1ps
module tb;
  reg [7:0] a, b; wire [7:0] s, p;
  gf8_add ua(.a(a), .b(b), .result(s));
  gf8_mul um(.a(a), .b(b), .result(p));
  integer i, j;
  initial begin
    for (i = 0; i < 256; i = i + 1)
      for (j = 0; j < 256; j = j + 1) begin
        a = i[7:0]; b = j[7:0]; #1;
        $display("%02x %02x %02x %02x", a, b, s, p);
      end
    $finish;
  end
endmodule
"""

def main():
    with tempfile.TemporaryDirectory() as d:
        tbp = os.path.join(d, "tb.v")
        outp = os.path.join(d, "sim")
        with open(tbp, "w") as f:
            f.write(TB)
        c = subprocess.run(["iverilog", "-g2012", "-o", outp,
                            os.path.join(SRC, "gf8_add.v"),
                            os.path.join(SRC, "gf8_mul.v"), tbp],
                           capture_output=True, text=True)
        if c.returncode != 0:
            print("iverilog FAILED:\n" + c.stderr); return 2
        r = subprocess.run(["vvp", outp], capture_output=True, text=True)
        lines = [l for l in r.stdout.splitlines() if len(l.split()) == 4]

    add_bad, mul_bad, n = [], [], 0
    max_add_ulp = max_mul_ulp = 0.0
    for l in lines:
        a, b, s, p = (int(x, 16) for x in l.split())
        n += 1
        ok_a, ea = check("add", a, b, s)
        ok_m, em = check("mul", a, b, p)
        if ea != float("inf"): max_add_ulp = max(max_add_ulp, ea)
        if em != float("inf"): max_mul_ulp = max(max_mul_ulp, em)
        if not ok_a: add_bad.append((a, b, s))
        if not ok_m: mul_bad.append((a, b, p))

    print(f"gf8 exhaustive cross-check: {n} pairs (tol {TOL_ULP:.0f} ULP)")
    print(f"  add: {n - len(add_bad)}/{n} pass; max error {max_add_ulp:.3f} ULP")
    print(f"  mul: {n - len(mul_bad)}/{n} pass; max error {max_mul_ulp:.3f} ULP")
    for name, bad in (("add", add_bad), ("mul", mul_bad)):
        for (a, b, o) in bad[:8]:
            print(f"  FAIL {name} {a:02x} {b:02x} -> {o:02x} "
                  f"(got {decode(o)}, ref {ref(name, a, b)})")
        if len(bad) > 8:
            print(f"  ... +{len(bad) - 8} more {name} fails")
    ok = not add_bad and not mul_bad
    print("RESULT:", "ALL PASS" if ok else "FAIL")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
