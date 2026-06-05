#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Verifies the blake3_anchor cryptographic-hash finding and its fix.
# The shipped blake3_anchor (the on-die DePIN RECEIPT signer, instantiated on the
# Gamma/Euler tops) implements BLAKE3's quarter-round G() WITHOUT the four XOR steps
# (d^=a before ROTR16/ROTR8, b^=c before ROTR12/ROTR7) -- the core diffusion -- so the
# digest is a near-linear function of the input, NOT preimage-resistant. This drives
# both the shipped RTL and the corrected blake3_anchor_v2 over several messages and
# checks: shipped == a no-XOR model (confirming the bug, no other defect), and v2 ==
# the real BLAKE3-G model (confirming the fix). Same round structure as the RTL
# (4 rounds, fixed message schedule) -- the XOR is the variable under test.
import os, subprocess, sys, tempfile, random
random.seed(3)

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")
M = 0xFFFFFFFF
IV = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
COL = [(0,4,8,12),(1,5,9,13),(2,6,10,14),(3,7,11,15)]
DIA = [(0,5,10,15),(1,6,11,12),(2,7,8,13),(3,4,9,14)]

def rotr(x, n): return ((x >> n) | (x << (32 - n))) & M

def model(mw, xor):
    v = IV + [IV[0], IV[1], IV[2], IV[3], 0, 0, 0, 0]
    for _ in range(4):
        mi = 0
        for (a, b, c, d) in COL + DIA:
            x, y = mw[2*mi], mw[2*mi+1]; mi += 1
            v[a] = (v[a] + v[b] + x) & M
            v[d] = rotr((v[d] ^ v[a]) if xor else v[d], 16)
            v[c] = (v[c] + v[d]) & M
            v[b] = rotr((v[b] ^ v[c]) if xor else v[b], 12)
            v[a] = (v[a] + v[b] + y) & M
            v[d] = rotr((v[d] ^ v[a]) if xor else v[d], 8)
            v[c] = (v[c] + v[d]) & M
            v[b] = rotr((v[b] ^ v[c]) if xor else v[b], 7)
    return [(v[i] ^ v[i+8]) & M for i in range(8)]

def pack(words):
    r = 0
    for i, w in enumerate(words): r |= w << (32 * i)
    return r

TB = """`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,start=0; reg [511:0] m; wire done; wire [255:0] dig; wire ok;
  {mod} u(.clk(clk),.rst_n(rst_n),.start(start),.m_in(m),.done(done),.digest(dig),.hash_ok(ok));
  always #5 clk=~clk; integer c;
  initial begin m=512'h{msg:0128x};
    @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
    @(negedge clk) start=1; @(negedge clk) start=0;
    c=0; while(!done && c<200) begin @(negedge clk); c=c+1; end
    $display("D %064h", dig); $finish; end endmodule
"""

def rtl_digest(mod_file, mod_name, m_in):
    with tempfile.TemporaryDirectory() as d:
        tbp, outp = os.path.join(d, "tb.v"), os.path.join(d, "sim")
        open(tbp, "w").write(TB.format(mod=mod_name, msg=m_in))
        c = subprocess.run(["iverilog", "-g2012", "-o", outp,
                            os.path.join(SRC, mod_file), tbp], capture_output=True, text=True)
        if c.returncode != 0:
            print("iverilog FAILED:\n" + c.stderr); sys.exit(2)
        out = subprocess.run(["vvp", outp], capture_output=True, text=True).stdout
        for ln in out.splitlines():
            if ln.startswith("D "): return int(ln.split()[1], 16)
    return None

def main():
    tests = [[(0x11111111*(i+1)) & M for i in range(16)]] + \
            [[random.randint(0, M) for _ in range(16)] for _ in range(5)]
    bug_ok = fix_ok = True
    for mw in tests:
        m_in = pack(mw)
        shipped = rtl_digest("blake3_anchor.v", "blake3_anchor", m_in)
        fixed   = rtl_digest("blake3_anchor_v2.v", "blake3_anchor_v2", m_in)
        broken_ref  = pack(model(mw, xor=False))
        correct_ref = pack(model(mw, xor=True))
        if shipped != broken_ref:  bug_ok = False
        if fixed   != correct_ref: fix_ok = False
        if shipped == correct_ref: fix_ok = False   # shipped must NOT be correct BLAKE3
    print("shipped blake3_anchor == no-XOR model (bug present, no other defect):", bug_ok)
    print("corrected blake3_anchor_v2 == real BLAKE3-G model (fix correct):     ", fix_ok)
    ok = bug_ok and fix_ok
    print("RESULT:", "CONFIRMED (bug characterized + fix verified)" if ok else "UNEXPECTED")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
