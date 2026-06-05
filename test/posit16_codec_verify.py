#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Exhaustive verification of posit16_to_gf16 (Posit16 es=2 -> GF16 decoder). The old
# decoder assumed fixed posit fields; a real posit has a variable-length regime. This
# checks the rewritten decoder over ALL 65536 posit codes against an INDEPENDENT
# value-based reference: decode the posit to its exact rational value (standard posit
# es=2 algorithm), then encode the nearest GF16 (round-half-up, matching the family
# encode). Non-circular -- the reference works from the value, not the RTL's bit
# slicing. Exit 0 iff all 65536 match.
import os, subprocess, sys, tempfile
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")
BIAS = 31

def posit_value(p):
    if p == 0:        return Fraction(0)
    if p == 0x8000:   return None            # NaR
    sign = p >> 15
    v = ((-p) & 0xFFFF) if sign else p
    s = format(v & 0x7FFF, "015b")           # 15-bit regime|exp|frac
    r0 = s[0]
    run = 0
    for c in s:
        if c == r0: run += 1
        else: break
    k = run - 1 if r0 == "1" else -run
    consumed = run + (1 if run < 15 else 0)
    rest = s[consumed:]
    e = int((rest + "00")[:2], 2)
    fb = rest[2:]
    frac = Fraction(int(fb, 2), 1 << len(fb)) if fb else Fraction(0)
    val = (1 + frac) * Fraction(2) ** (4 * k + e)
    return -val if sign else val

def flog2(x):
    n, d = x.numerator, x.denominator
    e = n.bit_length() - d.bit_length()
    return e if Fraction(2) ** e <= x else e - 1

def gf16_from_value(val):
    if val is None:        return 0xFE01     # NaR -> NaN
    if val == 0:           return 0x0000
    sign = 1 if val < 0 else 0
    a = -val if val < 0 else val
    E = flog2(a)
    m = (a / Fraction(2) ** E - 1) * 512      # mantissa in [0,512)
    mi = int(m)
    if m - mi >= Fraction(1, 2): mi += 1       # round-half-up
    if mi == 512: mi = 0; E += 1
    gexp = E + BIAS
    if gexp <= 0:   return sign << 15                      # underflow -> signed 0
    if gexp >= 63:  return (sign << 15) | (63 << 9)        # overflow -> signed Inf
    return (sign << 15) | (gexp << 9) | mi

def gf16_value(g):
    s = (g >> 15) & 1; e = (g >> 9) & 0x3F; m = g & 0x1FF
    if e == 0 and m == 0: return Fraction(0)
    if e == 0x3F:         return None              # Inf/NaN
    return (-1 if s else 1) * Fraction(512 + m) * Fraction(2) ** (e - BIAS - 9)

DEC_TB = """`timescale 1ns/1ps
module tb; reg [15:0] p; wire [15:0] g;
  posit16_to_gf16 u(.posit_in(p), .gf_out(g)); integer i;
  initial begin
    for (i=0;i<65536;i=i+1) begin p=i[15:0]; #1; $display("R %04h %04h", p, g); end
    $finish; end endmodule
"""
ENC_TB = """`timescale 1ns/1ps
module tb; reg [15:0] g; wire [15:0] p;
  gf16_to_posit16 u(.gf_in(g), .posit_out(p)); integer i;
  initial begin
    for (i=0;i<65536;i=i+1) begin g=i[15:0]; #1; $display("R %04h %04h", g, p); end
    $finish; end endmodule
"""

def run_tb(tb):
    with tempfile.TemporaryDirectory() as d:
        tbp, outp = os.path.join(d, "tb.v"), os.path.join(d, "sim")
        open(tbp, "w").write(tb)
        c = subprocess.run(["iverilog", "-g2012", "-o", outp,
                            os.path.join(SRC, "gf16_to_posit16.v"), tbp],
                           capture_output=True, text=True)
        if c.returncode != 0:
            print("iverilog FAILED:\n" + c.stderr); sys.exit(2)
        r = subprocess.run(["vvp", outp], capture_output=True, text=True)
        return [l.split()[1:] for l in r.stdout.splitlines() if l.startswith("R ")]

def main():
    ok = True
    # --- decoder: exhaustive vs value-based reference ---
    bad = 0
    for ah, bh in run_tb(DEC_TB):
        p, g = int(ah, 16), int(bh, 16)
        exp = gf16_from_value(posit_value(p))
        if g != exp:
            if bad < 6: print(f"  DEC FAIL posit={p:04x}: rtl={g:04x} ref={exp:04x}")
            bad += 1
    print(f"posit16_to_gf16 (decode) exhaustive: {65536-bad}/65536 pass")
    ok = ok and bad == 0

    # --- encoder: must produce the NEAREST posit to the gf16 value (posit codes are
    #     monotonic in value, so a value-adjacent code is the +-1 integer code) ---
    bad = 0
    for ah, bh in run_tb(ENC_TB):
        g, p = int(ah, 16), int(bh, 16)
        gv = gf16_value(g)
        if gv is None:                       # Inf/NaN -> NaR
            if p != 0x8000: bad += 1
            continue
        if gv == 0:                          # zero -> 0
            if p != 0x0000: bad += 1
            continue
        dp = posit_value(p)
        if dp is None: bad += 1; continue
        d0 = abs(dp - gv)
        worse = False
        for nb in ((p + 1) & 0xFFFF, (p - 1) & 0xFFFF):
            nv = posit_value(nb)
            if nv is not None and abs(nv - gv) < d0:   # a neighbour strictly closer
                worse = True
        if worse:
            if bad < 6: print(f"  ENC FAIL gf={g:04x}(val {float(gv):.4g}): p={p:04x} not nearest")
            bad += 1
    print(f"gf16_to_posit16 (encode) nearest-posit: {65536-bad}/65536 pass")
    ok = ok and bad == 0

    print("RESULT:", "ALL PASS" if ok else "FAIL")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
