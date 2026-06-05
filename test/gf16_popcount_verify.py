#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Functional verification of the VSA ternary-matmul popcount cores on the Gamma/Euler
# silicon top (reached via vsa_matmul_8x8 / vsa_matmul_16x16): gf16_popcount (8-elem)
# and gf16_popcount16 (16-elem). Each computes the ternary inner product of two
# N-element vectors (2-bit elements: 00=+1, 01=-1, 10/11=0): result = (#same-sign
# active pairs) - (#diff-sign active pairs). 3-stage pipeline. Drives random vectors
# and checks the result (3 cycles later, in order) against a reference.
import os, subprocess, sys, tempfile, random
random.seed(99)

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")
N = 4000

# module, file, N_ELEMS, row-bit-width
CORES = [
    ("gf16_popcount",   "gf16_popcount.v",   8,  16),
    ("gf16_popcount16", "gf16_popcount16.v", 16, 32),
]

def ref(a_row, b_row, elems):
    acc = 0
    for k in range(elems):
        ae = (a_row >> (2 * k)) & 3
        be = (b_row >> (2 * k)) & 3
        if (ae & 2) == 0 and (be & 2) == 0:
            acc += 1 if (ae & 1) == (be & 1) else -1
    return acc & 0xFF

TB = """`timescale 1ns/1ps
module tb;
  reg clk=0, rst_n=0, valid_in=0; reg [{w1}:0] a_row, b_row;
  wire valid_out; wire [7:0] result;
  reg [{w1}:0] av [0:{nm1}]; reg [{w1}:0] bv [0:{nm1}];
  {mod} #(.N_ELEMS({elems}), .LATENCY(3)) u
    (.clk(clk), .rst_n(rst_n), .valid_in(valid_in), .a_row(a_row), .b_row(b_row),
     .valid_out(valid_out), .result(result));
  always #5 clk = ~clk;
  integer i;
  initial begin
    $readmemh("{af}", av); $readmemh("{bf}", bv);
    @(negedge clk) rst_n = 0; @(negedge clk) rst_n = 1;
    fork
      begin
        for (i = 0; i < {n}; i = i + 1)
          @(negedge clk) begin valid_in = 1; a_row = av[i]; b_row = bv[i]; end
        @(negedge clk) valid_in = 0;
      end
      begin
        integer j; j = 0;
        while (j < {n}) begin
          @(posedge clk);
          if (valid_out) begin $display("R %0d %02h", j, result); j = j + 1; end
        end
      end
    join
    $finish;
  end
endmodule
"""

def run_core(mod, fn, elems, w):
    mask = (1 << w) - 1
    pairs = [(random.randint(0, mask), random.randint(0, mask)) for _ in range(N)]
    with tempfile.TemporaryDirectory() as d:
        hexw = (w + 3) // 4
        af, bf = os.path.join(d, "a.hex"), os.path.join(d, "b.hex")
        open(af, "w").write("\n".join(f"%0{hexw}x" % a for a, _ in pairs))
        open(bf, "w").write("\n".join(f"%0{hexw}x" % b for _, b in pairs))
        tbp, outp = os.path.join(d, "tb.v"), os.path.join(d, "sim")
        open(tbp, "w").write(TB.format(w1=w - 1, nm1=N - 1, n=N, mod=mod,
                                       elems=elems, af=af, bf=bf))
        c = subprocess.run(["iverilog", "-g2012", "-o", outp, os.path.join(SRC, fn), tbp],
                           capture_output=True, text=True)
        if c.returncode != 0:
            print(f"  {mod}: iverilog FAILED\n{c.stderr}"); return None
        r = subprocess.run(["vvp", outp], capture_output=True, text=True, timeout=120)
        got = {}
        for ln in r.stdout.splitlines():
            if ln.startswith("R "):
                _, idx, hx = ln.split(); got[int(idx)] = int(hx, 16)
    bad = sum(1 for i, (a, b) in enumerate(pairs)
              if i not in got or got[i] != ref(a, b, elems))
    return len(pairs), bad

def main():
    ok = True
    print("VSA popcount cores (ternary inner product) functional check:")
    for mod, fn, elems, w in CORES:
        res = run_core(mod, fn, elems, w)
        if res is None:
            ok = False; continue
        n, bad = res
        print(f"  {mod} ({elems} elems): {n-bad}/{n} pass")
        ok = ok and bad == 0
    print("RESULT:", "ALL PASS" if ok else "FAIL")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
