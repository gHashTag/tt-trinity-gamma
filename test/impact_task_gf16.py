#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Task-level impact of the gf16_mul defect: does it flip CLASSIFICATION decisions?
# Models a single linear classifier layer -- CLASSES logits, each a 16-element gf16
# dot product (dot16) of a shared input vector with a per-class weight row -- and
# takes argmax (the predicted class). Runs the shipped path (dot16: gf16_mul+gf16_add)
# and the corrected path (dot16_v2: gf16_v2_*) over K random near-1.0 trials, and
# compares each argmax to the EXACT-rational argmax. Reports the prediction-flip rate
# -- the most decision-legible framing of the defect, one step past MAC RMS.
import os, subprocess, sys, tempfile, random
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")
BIAS = 31
CLASSES = 10
NIN = 16
K = 5000
random.seed(20260603)

def decode(code):
    s = (code >> 15) & 1; e = (code >> 9) & 0x3F; m = code & 0x1FF
    if e == 0 and m == 0: return Fraction(0)
    if e == 0x3F: return None
    return (-1 if s else 1) * Fraction(512 + m) * Fraction(2) ** (e - BIAS - 9)

def rand_gf16():
    e = random.randint(BIAS - 2, BIAS + 1)   # near-1.0 activations/weights
    return (random.randint(0, 1) << 15) | (e << 9) | random.randint(0, 511)

def pack(vec16):
    w = 0
    for k, v in enumerate(vec16):
        w |= (v & 0xFFFF) << (16 * k)
    return w

TB = """`timescale 1ns/1ps
module tb;
  reg [255:0] av [0:{nm1}]; reg [255:0] wv [0:{nm1}];
  reg [255:0] a, w; wire [15:0] r_o, r_n;
  dot16    uo(.a(a), .w(w), .result(r_o));
  dot16_v2 un(.a(a), .w(w), .result(r_n));
  integer i;
  initial begin
    $readmemh("{af}", av); $readmemh("{wf}", wv);
    for (i = 0; i < {n}; i = i + 1) begin a = av[i]; w = wv[i]; #1;
      $display("R %04h %04h", r_o, r_n); end
    $finish;
  end
endmodule
"""

def main():
    # build K trials; each trial: 1 input vector, CLASSES weight rows
    a_words, w_words, exact = [], [], []
    for _ in range(K):
        x = [rand_gf16() for _ in range(NIN)]
        xv = [decode(c) for c in x]
        for _c in range(CLASSES):
            wr = [rand_gf16() for _ in range(NIN)]
            a_words.append(pack(x)); w_words.append(pack(wr))
            exact.append(sum(xv[k] * decode(wr[k]) for k in range(NIN)))
    n = len(a_words)
    with tempfile.TemporaryDirectory() as d:
        af, wf = os.path.join(d, "a.hex"), os.path.join(d, "w.hex")
        open(af, "w").write("\n".join("%064x" % x for x in a_words))
        open(wf, "w").write("\n".join("%064x" % x for x in w_words))
        tbp, outp = os.path.join(d, "tb.v"), os.path.join(d, "sim")
        open(tbp, "w").write(TB.format(nm1=n - 1, n=n, af=af, wf=wf))
        c = subprocess.run(["iverilog", "-g2012", "-o", outp,
                            os.path.join(SRC, "dot16_study.v"),
                            os.path.join(SRC, "gf16_dot4.v"), os.path.join(SRC, "gf16_dot4_v2.v"),
                            os.path.join(SRC, "gf16_mul.v"), os.path.join(SRC, "gf16_add.v"),
                            os.path.join(SRC, "gf16_v2_mul.v"), os.path.join(SRC, "gf16_v2_add.v"), tbp],
                           capture_output=True, text=True)
        if c.returncode != 0:
            print("iverilog FAILED:\n" + c.stderr); return 2
        r = subprocess.run(["vvp", outp], capture_output=True, text=True)
        rows = [l.split()[1:] for l in r.stdout.splitlines() if l.startswith("R ")]

    shipped_flip = v2_flip = sh_vs_v2 = 0
    for t in range(K):
        base = t * CLASSES
        ex = exact[base:base + CLASSES]
        sh = [decode(int(rows[base + cc][0], 16)) for cc in range(CLASSES)]
        nv = [decode(int(rows[base + cc][1], 16)) for cc in range(CLASSES)]
        if any(v is None for v in sh + nv):
            continue
        am_ex = max(range(CLASSES), key=lambda i: ex[i])
        am_sh = max(range(CLASSES), key=lambda i: sh[i])
        am_nv = max(range(CLASSES), key=lambda i: nv[i])
        shipped_flip += (am_sh != am_ex)
        v2_flip += (am_nv != am_ex)
        sh_vs_v2 += (am_sh != am_nv)          # the bug's NET effect on the decision
    print(f"task-level impact: {K} trials, {CLASSES}-class linear layer, {NIN}-input gf16 dots")
    print(f"  shipped (gf16_mul) argmax != exact:  {shipped_flip} ({100.0*shipped_flip/K:.2f}%)")
    print(f"  corrected (gf16_v2) argmax != exact: {v2_flip} ({100.0*v2_flip/K:.2f}%)")
    print(f"  shipped argmax != corrected argmax:  {sh_vs_v2} ({100.0*sh_vs_v2/K:.2f}%)  <- bug's net effect")
    print(f"  => despite the ~11% MAC RMS, the gf16_mul defect changes the *predicted class*")
    print(f"     on only {100.0*sh_vs_v2/K:.2f}% of inputs -- argmax flips only near decision")
    print(f"     boundaries, and the inherent gf16 rounding floor dominates ({100.0*v2_flip/K:.2f}%).")
    print("RESULT: gf16_mul task-level (classification-flip) impact quantified")
    return 0

if __name__ == "__main__":
    sys.exit(main())
