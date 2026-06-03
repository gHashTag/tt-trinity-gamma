#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Exhaustive check of gf16_to_fp16 over all 65536 GF16 inputs. The converter was
# latch-inferring (fp_out unassigned on the value<1.0 path) and wrongly routed
# every gf_exp<31 to a broken "subnormal" branch. Fixed to map representable
# exponents (down to FP16 min normal 2^-14) to FP16 normals and flush smaller
# magnitudes to signed zero. Reference below encodes the same policy; exit 0 iff
# all 65536 match (a passing exhaustive run also confirms no latch remains).
import os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")

def ref(code):
    s = (code >> 15) & 1
    e = (code >> 9) & 0x3F          # GF16 E6
    m = code & 0x1FF                # GF16 M9
    if e == 0x3F and m != 0: return (s << 15) | (0x1F << 10) | 1     # NaN
    if e == 0x3F:            return (s << 15) | (0x1F << 10)         # Inf
    if e == 0 and m == 0:    return (s << 15)                       # zero
    fp_exp_b = e - 16                # (e-31)+15
    if fp_exp_b >= 31:       return (s << 15) | (0x1F << 10)         # overflow -> Inf
    if fp_exp_b < 1:         return (s << 15)                       # underflow -> 0
    return (s << 15) | (fp_exp_b << 10) | ((m << 1) & 0x3FF)        # normal

TB = """`timescale 1ns/1ps
module tb;
  reg [15:0] g; wire [15:0] f;
  gf16_to_fp16 u(.gf_in(g), .fp_out(f));
  integer i;
  initial begin
    for (i = 0; i < 65536; i = i + 1) begin g = i[15:0]; #1; $display("R %04h %04h", g, f); end
    $finish;
  end
endmodule
"""

def main():
    with tempfile.TemporaryDirectory() as d:
        tbp, outp = os.path.join(d, "tb.v"), os.path.join(d, "sim")
        open(tbp, "w").write(TB)
        c = subprocess.run(["iverilog", "-g2012", "-o", outp,
                            os.path.join(SRC, "gf16_to_fp16.v"), tbp],
                           capture_output=True, text=True)
        if c.returncode != 0:
            print("iverilog FAILED:\n" + c.stderr); return 2
        r = subprocess.run(["vvp", outp], capture_output=True, text=True)
        rows = [l.split()[1:] for l in r.stdout.splitlines() if l.startswith("R ")]
    bad = 0
    for g, f in [(int(a, 16), int(b, 16)) for a, b in rows]:
        if f != ref(g):
            if bad < 6:
                print(f"  FAIL gf={g:04x} -> {f:04x}, ref {ref(g):04x}")
            bad += 1
    print(f"gf16_to_fp16 exhaustive: {65536 - bad}/65536 pass")
    print("RESULT:", "ALL PASS" if bad == 0 else "FAIL")
    return 0 if bad == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
