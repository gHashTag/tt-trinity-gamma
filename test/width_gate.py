#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# CI gate for the recurring "a field one bit too narrow" defect class: sized literals
# that overflow their width (value too large for N bit) and out-of-range bit-selects
# (SELRANGE). Every active arithmetic defect in the GoldenFloat audit was an instance
# (gf16_mul mantissa, bitnet neuron_base, gf_formats IDs, int4_quantizer dequant).
# Lints every src/*.v with verilator and FAILS on any such defect, EXCEPT in the
# allow-listed frozen-silicon files (their source must match the taped-out die; the
# correction lives in the *_v2 modules / the t27 master).
#
# Run from the repo root: python3 test/width_gate.py    (exit 0 = clean)
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC  = os.path.join(ROOT, "src")
SIG  = ("Value too large for", "SELRANGE", "Selection index out of range", "Extracting")
LOC  = re.compile(r"\.v:\d+:\d+:")
# Frozen-as-taped-out silicon source with a documented defect (fix is in *_v2 /
# the t27 master); not a regression, so it must not fail the gate.
ALLOWLIST = {"gf16_mul.v"}

def main():
    if not os.path.isdir(SRC):
        print(f"no src dir at {SRC}"); return 0
    fails = []
    for fn in sorted(os.listdir(SRC)):
        if not fn.endswith(".v"):
            continue
        out = subprocess.run(["verilator", "--lint-only", "-Wall", os.path.join(SRC, fn)],
                             capture_output=True, text=True).stderr
        hits = sorted(set(l.strip() for l in out.splitlines()
                          if any(s in l for s in SIG) and "MULTITOP" not in l and LOC.search(l)))
        if not hits:
            continue
        tag = "ALLOWED (frozen silicon)" if fn in ALLOWLIST else "FAIL"
        print(f"### {fn}: {tag}")
        for h in hits[:6]:
            print("   ", h.replace("%Warning-", ""))
        if fn not in ALLOWLIST:
            fails.append(fn)
    if fails:
        print(f"\nwidth_gate: FAIL -- {len(fails)} file(s) with a new width/range defect: "
              f"{', '.join(fails)}")
        return 1
    print("\nwidth_gate: PASS -- no new width/range defects "
          f"(allow-listed frozen: {', '.join(sorted(ALLOWLIST))})")
    return 0

if __name__ == "__main__":
    sys.exit(main())
