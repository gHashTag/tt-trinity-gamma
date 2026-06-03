#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Verify the corrected gf16_v2_{add,mul} AND quantify the original gf16 silicon
# rung's bug domain. Runs OLD (gf16_add/gf16_mul) and NEW (gf16_v2_*) over the same
# pairs through iverilog and compares each to an exact-rational reference, across
# three regimes: mid-range (both should agree), subtractive cancellation (old add
# is imprecise), and large-magnitude products (old mul overflows to zero).
#
# Purpose: give a respin/no-respin decision basis -- WHERE the shipped gf16 is
# wrong and whether the corrected v2 is faithful. Exit 0 iff gf16_v2 is faithful
# (<=1 ULP add, <=0.5 ULP mul, correct overflow). The OLD-unit stats are reported,
# not asserted (the die is frozen).
import os, subprocess, sys, tempfile
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")
E, M, total = 6, 9, 16
BIAS = 2 ** (E - 1) - 1
EMAX = 2 ** E - 1

def decode(code):
    s = (code >> (E + M)) & 1
    e = (code >> M) & (2 ** E - 1)
    m = code & (2 ** M - 1)
    sign = -1 if s else 1
    if e == 0 and m == 0:  return ("zero",)
    if e == EMAX and m == 0: return ("inf", s)
    if e == EMAX:          return ("nan",)
    return ("num", Fraction(sign * (2 ** M + m)) * Fraction(2) ** (e - BIAS - M))

def flog2(x):
    n, d = x.numerator, x.denominator
    e = n.bit_length() - d.bit_length()
    return e if Fraction(2) ** e <= x else e - 1

OVF = Fraction(2) ** (EMAX - BIAS)        # |x| >= this is clearly overflow -> Inf
MINN = Fraction(2 ** M + 1, 2 ** M) * Fraction(2) ** (-BIAS)
MAXF = Fraction(2 ** (M + 1) - 1, 2 ** M) * Fraction(2) ** (EMAX - 1 - BIAS)  # max finite

def near_or_inf(out):                     # acceptable in the [MAXF, OVF) round zone
    d = decode(out)
    return d[0] == "inf" or (d[0] == "num" and abs(d[1]) == MAXF)

def gen_pairs():
    pairs = []
    def enc(s, e, m): return (s << (E + M)) | (e << M) | m
    # 1) mid-range: exps near bias, assorted mantissas/signs
    MS = [0, 1, 2, 256, 511, 510, 300]
    for da in (-2, -1, 0, 1, 2):
        for db in (-2, -1, 0, 1, 2):
            for ma in MS:
                for mb in MS:
                    for sa, sb in ((0, 0), (1, 0)):
                        pairs.append((enc(sa, BIAS + da, ma), enc(sb, BIAS + db, mb)))
    # 2) subtractive cancellation: same/near exp, opposite signs, close mantissas
    for e in (BIAS - 1, BIAS, BIAS + 1):
        for ma in range(0, 512, 17):
            for d in (0, 1, 2, 3, 8, 33):
                mb = (ma + d) % 512
                pairs.append((enc(0, e, ma), enc(1, e, mb)))
                pairs.append((enc(0, e + 1, ma), enc(1, e, mb)))
    # 3) large-magnitude products that overflow (old mul -> 0)
    for ea in (EMAX - 1, EMAX - 2, EMAX - 3):
        for eb in (EMAX - 1, EMAX - 2, EMAX - 3):
            for ma in (0, 256, 511):
                for mb in (0, 256, 511):
                    pairs.append((enc(0, ea, ma), enc(0, eb, mb)))
    return pairs

TB = """`timescale 1ns/1ps
module tb;
  reg [15:0] av [0:{nm1}]; reg [15:0] bv [0:{nm1}];
  reg [15:0] a, b; wire [15:0] sa_o, sa_n, pm_o, pm_n;
  gf16_add     ao(.a(a), .b(b), .result(sa_o));
  gf16_v2_add  an(.a(a), .b(b), .result(sa_n));
  gf16_mul     mo(.a(a), .b(b), .result(pm_o));
  gf16_v2_mul  mn(.a(a), .b(b), .result(pm_n));
  integer i;
  initial begin
    $readmemh("{af}", av); $readmemh("{bf}", bv);
    for (i = 0; i < {n}; i = i + 1) begin
      a = av[i]; b = bv[i]; #1;
      $display("R %h %h %h %h", sa_o, sa_n, pm_o, pm_n);
    end
    $finish;
  end
endmodule
"""

def ulp_err(out, true):
    do = decode(out)
    if true == 0:
        return None if do[0] == "zero" else Fraction(-1)   # -1 = wrong kind
    le = flog2(abs(true))
    if do[0] != "num":
        return Fraction(-1)
    if (do[1] < 0) != (true < 0):
        return Fraction(-1)
    return abs(do[1] - true) / (Fraction(2) ** (le - M))

def main():
    pairs = gen_pairs(); n = len(pairs)
    with tempfile.TemporaryDirectory() as d:
        af, bf = os.path.join(d, "a.hex"), os.path.join(d, "b.hex")
        open(af, "w").write("\n".join("%x" % a for a, _ in pairs))
        open(bf, "w").write("\n".join("%x" % b for _, b in pairs))
        tbp, outp = os.path.join(d, "tb.v"), os.path.join(d, "sim")
        open(tbp, "w").write(TB.format(nm1=n - 1, n=n, af=af, bf=bf))
        srcs = [os.path.join(SRC, x) for x in
                ("gf16_add.v", "gf16_v2_add.v", "gf16_mul.v", "gf16_v2_mul.v")]
        c = subprocess.run(["iverilog", "-g2012", "-o", outp, *srcs, tbp],
                           capture_output=True, text=True)
        if c.returncode != 0:
            print("iverilog FAILED:\n" + c.stderr); return 2
        r = subprocess.run(["vvp", outp], capture_output=True, text=True)
        rows = [l.split()[1:] for l in r.stdout.splitlines() if l.startswith("R ")]

    # tallies
    add_old_max = add_new_max = Fraction(0)
    add_diff = add_old_bad = 0
    mul_ovf = mul_old_ovf_ok = mul_new_ovf_ok = 0
    mul_old_max = mul_new_max = Fraction(0)
    new_fail = []
    for (a, b), (so, sn, po, pn) in zip(pairs, [tuple(int(x, 16) for x in row) for row in rows]):
        da, db = decode(a), decode(b)
        if da[0] != "num" or db[0] != "num":
            continue
        # ---- ADD ----
        ta = da[1] + db[1]
        if ta != 0 and MINN <= abs(ta) < MAXF:        # clean in-range
            eo, en = ulp_err(so, ta), ulp_err(sn, ta)
            if eo is not None and eo >= 0: add_old_max = max(add_old_max, eo)
            if en is not None and en >= 0: add_new_max = max(add_new_max, en)
            if so != sn: add_diff += 1
            if eo is not None and (eo < 0 or eo > Fraction(1, 2)): add_old_bad += 1
            if en is None or en < 0 or en > 1:
                new_fail.append(("add", a, b, sn, float(en) if en and en >= 0 else -1))
        elif abs(ta) >= MAXF and not near_or_inf(sn):  # overflow round zone
            new_fail.append(("add-ovf", a, b, sn, -1))
        # ---- MUL ----
        tm = da[1] * db[1]
        if abs(tm) >= OVF:                            # clearly overflow -> Inf
            mul_ovf += 1
            if decode(po)[0] == "inf": mul_old_ovf_ok += 1
            if decode(pn)[0] == "inf": mul_new_ovf_ok += 1
            else: new_fail.append(("mul-ovf", a, b, pn, -1))
        elif tm != 0 and MINN <= abs(tm) < MAXF:      # clean in-range
            eo, en = ulp_err(po, tm), ulp_err(pn, tm)
            if eo is not None and eo >= 0: mul_old_max = max(mul_old_max, eo)
            if en is not None and en >= 0: mul_new_max = max(mul_new_max, en)
            if en is None or en < 0 or en > Fraction(1, 2):
                new_fail.append(("mul", a, b, pn, float(en) if en and en >= 0 else -1))
        elif abs(tm) >= MAXF and not near_or_inf(pn):  # overflow round zone
            new_fail.append(("mul-ovf", a, b, pn, -1))

    print(f"gf16 old-vs-corrected, {n} pairs:")
    print(f"  ADD  old max {float(add_old_max):.2f} ULP, NEW max {float(add_new_max):.4f} ULP")
    print(f"       old imprecise (> 0.5 ULP) on {add_old_bad} pairs; old!=new on {add_diff}")
    print(f"  MUL  in-range: old max {float(mul_old_max):.2f} ULP, NEW max {float(mul_new_max):.4f} ULP")
    print(f"       overflow cases {mul_ovf}: old->Inf {mul_old_ovf_ok}, NEW->Inf {mul_new_ovf_ok}")
    ok = (not new_fail) and add_new_max <= 1 and mul_new_max <= Fraction(1, 2)
    for f in new_fail[:6]:
        print("   NEW FAIL", f)
    print("RESULT:", "gf16_v2 FAITHFUL" if ok else "gf16_v2 FAIL")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
