#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Special-value cross-check for every gfN_{add,mul}. Confirms each unit's Inf/NaN/
# overflow handling is correct AND that the emitted Inf/NaN round-trip under the
# decode convention (Inf = exp-all-ones & mant==0; NaN = exp-all-ones & mant!=0).
#
# This catches the bug fixed 2026-06: gf12/20/24/32/64/128 emitted "Inf" constants
# with a nonzero mantissa field, so overflow produced a value that decodes as NaN
# (and would not round-trip). Each case checks the KIND of the result (and the sign
# for Inf). Exit 0 iff all rungs pass all cases.
import os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")

RUNGS = {  # name: (total, E, M)
    "gf4": (4, 1, 2), "gf8": (8, 3, 4), "gf12": (12, 4, 7), "gf16": (16, 6, 9),
    "gf20": (20, 7, 12), "gf24": (24, 9, 14), "gf32": (32, 12, 19),
    "gf64": (64, 24, 39), "gf128": (128, 48, 79), "gf256": (256, 97, 158),
}
# gf16 is the silicon-[Verified] rung and is left untouched (source must match the
# fabricated die). Its overflow cases here are INFORMATIONAL only: gf16_mul flushes
# a very-large product to zero instead of Inf (final_exp[6] aliases overflow to the
# underflow path) -- a documented latent bug never exercised by near-1.0 workloads.
LEGACY_INFORMATIONAL = {"gf16"}

def kind(code, E, M):
    s = (code >> (E + M)) & 1
    e = (code >> M) & ((1 << E) - 1)
    m = code & ((1 << M) - 1)
    emax = (1 << E) - 1
    if e == emax and m == 0: return ("inf", s)
    if e == emax:            return ("nan",)
    if e == 0 and m == 0:    return ("zero",)
    return ("num", s)

def operands(total, E, M):
    emax = (1 << E) - 1
    bias = (1 << (E - 1)) - 1
    sgn  = 1 << (total - 1)
    pinf = emax << M
    ninf = sgn | pinf
    nan  = pinf | 1
    zero = 0
    # a finite value: 1.0 if bias>0 else the smallest finite (gf4: 1.25 = m1)
    one  = (bias << M) if bias > 0 else 1
    maxf = ((emax - 1) << M) | ((1 << M) - 1)   # largest finite magnitude
    return dict(pinf=pinf, ninf=ninf, nan=nan, zero=zero, one=one, maxf=maxf)

def cases(o):
    # (op, a, b, expected_kind_tuple)
    return [
        ("add", o["pinf"], o["one"],  ("inf", 0)),
        ("add", o["pinf"], o["ninf"], ("nan",)),
        ("add", o["nan"],  o["one"],  ("nan",)),
        ("add", o["maxf"], o["maxf"], ("inf", 0)),   # overflow -> +Inf (round-trip!)
        ("mul", o["one"],  o["pinf"], ("inf", 0)),
        ("mul", o["zero"], o["pinf"], ("nan",)),
        ("mul", o["nan"],  o["one"],  ("nan",)),
        ("mul", o["maxf"], o["maxf"], ("inf", 0)),   # overflow -> +Inf (round-trip!)
    ]

TB = """`timescale 1ns/1ps
module tb;
  reg [{hi}:0] a, b; wire [{hi}:0] s, p;
  {name}_add ua(.a(a), .b(b), .result(s));
  {name}_mul um(.a(a), .b(b), .result(p));
  initial begin
{body}
    $finish;
  end
endmodule
"""

def run_rung(name):
    total, E, M = RUNGS[name]
    o = operands(total, E, M)
    cs = cases(o)
    body = []
    for i, (op, a, b, _) in enumerate(cs):
        w = total
        body.append(f"    a = {w}'h{a:X}; b = {w}'h{b:X}; #1; "
                    f"$display(\"R {i} {op} %h\", {'s' if op=='add' else 'p'});")
    tb = TB.format(hi=total - 1, name=name, body="\n".join(body))
    with tempfile.TemporaryDirectory() as d:
        tbp, outp = os.path.join(d, "tb.v"), os.path.join(d, "sim")
        open(tbp, "w").write(tb)
        c = subprocess.run(["iverilog", "-g2012", "-o", outp,
                            os.path.join(SRC, name + "_add.v"),
                            os.path.join(SRC, name + "_mul.v"), tbp],
                           capture_output=True, text=True)
        if c.returncode != 0:
            print(f"  {name}: iverilog FAILED\n{c.stderr}"); return None
        r = subprocess.run(["vvp", outp], capture_output=True, text=True)
        got = {}
        for ln in r.stdout.splitlines():
            if ln.startswith("R "):
                _, idx, op, hx = ln.split()
                got[int(idx)] = int(hx, 16)
    bad = []
    for i, (op, a, b, exp) in enumerate(cs):
        k = kind(got[i], E, M)
        ok = (k[0] == exp[0]) and (exp[0] != "inf" or k[1] == exp[1])
        if not ok:
            bad.append((op, a, b, got[i], k, exp))
    return cs, bad

def main():
    all_ok = True
    print("gfN special-value cross-check (Inf / NaN / overflow round-trip):")
    for name in RUNGS:
        res = run_rung(name)
        if res is None:
            all_ok = False; continue
        cs, bad = res
        legacy = name in LEGACY_INFORMATIONAL
        tag = "PASS" if not bad else ("FAIL" if not legacy else "INFO (legacy)")
        print(f"  {name}: {len(cs) - len(bad)}/{len(cs)} cases -> {tag}")
        for (op, a, b, got, k, exp) in bad:
            print(f"      {op} {a:x} {b:x} -> {got:x} decodes {k}, expected {exp}")
        if bad and not legacy:
            all_ok = False
    print("RESULT:", "ALL PASS" if all_ok else "FAIL")
    return 0 if all_ok else 1

if __name__ == "__main__":
    sys.exit(main())
