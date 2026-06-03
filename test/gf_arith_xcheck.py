#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# test/gf_arith_xcheck.py
#
# Cross-check the GoldenFloat rung arithmetic units (gfN_add / gfN_mul) against
# the float semantics they implement, using exponent arithmetic that is exact for
# every rung size (no host-float overflow for gf64/gf128).
#
# Two probes per rung (mantissa = 0, so the result is a pure exponent check):
#   1+1 -> exponent should be bias+1 (i.e. 2.0)
#   2*1 -> exponent should be bias+1 (i.e. 2.0)
# A rung whose ADD or MUL does not produce bias+1 has a normalization bug.
#
# Result (2026-06): ONLY gf16 (the [Verified] rung) is correct; every other rung
# has a broken add and/or mul -- different bugs per rung, indicating the generated
# units were never semantically cross-checked. GF16's add/mul are the reference
# for a correct fix. See docs/GF_ARITH_FINDINGS.md.
#
# Exit code = number of broken rungs (0 = all correct). Diagnostic; not wired into
# CI so it does not break the pipeline while the rungs are unfixed.
# Run: python3 test/gf_arith_xcheck.py

import os
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "src")

# rung -> (exponent bits E, mantissa bits M). bias = 2^(E-1) - 1.
# gf256 omitted: its stored bias is itself [Open conjecture] (see family doc).
RUNGS = {
    "gf4": (1, 2), "gf8": (3, 4), "gf12": (4, 7), "gf16": (6, 9),
    "gf20": (7, 12), "gf24": (9, 14), "gf32": (12, 19), "gf64": (24, 39),
    "gf128": (48, 79),
}


def bias(E):
    return (1 << (E - 1)) - 1


def probe(rung, E, M):
    W = 1 + E + M
    b = bias(E)
    one = b << M            # +1.0 : exp=bias, mant=0
    two = (b + 1) << M       # +2.0 : exp=bias+1, mant=0
    tb = (
        f"`timescale 1ns/1ps\n"
        f"module tb; reg [{W-1}:0] a,b; wire [{W-1}:0] s,p;\n"
        f" {rung}_add ad(.a(a),.b(b),.result(s));\n"
        f" {rung}_mul mu(.a(a),.b(b),.result(p));\n"
        f" initial begin\n"
        f"   a={W}'d{one}; b={W}'d{one}; #1; $display(\"ADD %0d\", s[{E+M-1}:{M}]);\n"
        f"   a={W}'d{two}; b={W}'d{one}; #1; $display(\"MUL %0d\", p[{E+M-1}:{M}]);\n"
        f"   $finish; end\nendmodule\n"
    )
    d = tempfile.mkdtemp()
    with open(os.path.join(d, "tb.v"), "w") as f:
        f.write(tb)
    add = os.path.join(SRC, f"{rung}_add.v")
    mul = os.path.join(SRC, f"{rung}_mul.v")
    c = subprocess.run(["iverilog", "-g2012", "-o", os.path.join(d, "x"),
                        add, mul, os.path.join(d, "tb.v")],
                       capture_output=True, text=True)
    if c.returncode != 0:
        return None
    out = subprocess.run(["vvp", os.path.join(d, "x")], capture_output=True, text=True).stdout
    res = {}
    for ln in out.splitlines():
        q = ln.split()
        if len(q) == 2 and q[0] in ("ADD", "MUL"):
            res[q[0]] = int(q[1])
    return res


def main():
    if not (shutil_which("iverilog") and shutil_which("vvp")):
        print("SKIP: iverilog/vvp not found.")
        return 0
    broken = []
    print(f"{'rung':6s} {'want':>16} {'ADD':>16} {'MUL':>16}  verdict")
    for rung, (E, M) in RUNGS.items():
        r = probe(rung, E, M)
        if r is None:
            print(f"{rung:6s}  (compile/run error)")
            continue
        want = bias(E) + 1
        add_ok = r.get("ADD") == want
        mul_ok = r.get("MUL") == want
        verdict = "OK" if (add_ok and mul_ok) else (
            "BROKEN add+mul" if not add_ok and not mul_ok else
            ("BROKEN mul" if add_ok else "BROKEN add"))
        if not (add_ok and mul_ok):
            broken.append(rung)
        print(f"{rung:6s} {want:>16} {r.get('ADD'):>16} {r.get('MUL'):>16}  {verdict}")
    print("\n" + "=" * 60)
    print(f"{len(RUNGS)-len(broken)}/{len(RUNGS)} rungs correct; "
          f"broken: {', '.join(broken) if broken else 'none'}")
    print("Reference for a correct fix: gf16 (the only [Verified] rung).")
    return len(broken)


def shutil_which(x):
    from shutil import which
    return which(x)


if __name__ == "__main__":
    sys.exit(main())
