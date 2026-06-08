#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Wave-5 verification: blake3_anchor_v3 == a real 7-round + message-permuted BLAKE3-G
# reference, and != the reduced 4-round/no-permutation v2 model.
#
# v2 (loop 146) restored the four XOR diffusion steps but kept the "mini" reductions
# (4 rounds, no per-round message permutation). v3 (Wave-5) implements the full BLAKE3
# mixing schedule: 7 rounds with PERM = [2,6,3,10,7,0,4,13,1,11,12,5,9,14,15,8]
# applied between rounds. This drives the v3 RTL and checks it matches the full model.
import os, subprocess, sys, tempfile, random
random.seed(5)
HERE = os.path.dirname(os.path.abspath(__file__)); SRC = os.path.join(HERE, "..", "src")
M = 0xFFFFFFFF
IV = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
COL = [(0,4,8,12),(1,5,9,13),(2,6,10,14),(3,7,11,15)]
DIA = [(0,5,10,15),(1,6,11,12),(2,7,8,13),(3,4,9,14)]
PERM = [2,6,3,10,7,0,4,13,1,11,12,5,9,14,15,8]
def rotr(x,n): return ((x>>n)|(x<<(32-n))) & M

def model(mw, rounds, permute):
    v = IV + [IV[0],IV[1],IV[2],IV[3],0,0,0,0]
    m = list(mw)
    for _ in range(rounds):
        mi = 0
        for (a,b,c,d) in COL+DIA:
            x,y = m[2*mi], m[2*mi+1]; mi += 1
            v[a]=(v[a]+v[b]+x)&M; v[d]=rotr(v[d]^v[a],16)
            v[c]=(v[c]+v[d])&M;   v[b]=rotr(v[b]^v[c],12)
            v[a]=(v[a]+v[b]+y)&M; v[d]=rotr(v[d]^v[a],8)
            v[c]=(v[c]+v[d])&M;   v[b]=rotr(v[b]^v[c],7)
        if permute: m = [m[PERM[i]] for i in range(16)]
    return [(v[i]^v[i+8])&M for i in range(8)]

def pack(words):
    r=0
    for i,w in enumerate(words): r|=w<<(32*i)
    return r

TB = """`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,start=0; reg [511:0] m; wire done; wire [255:0] dig; wire ok;
  blake3_anchor_v3 u(.clk(clk),.rst_n(rst_n),.start(start),.m_in(m),.done(done),.digest(dig),.hash_ok(ok));
  always #5 clk=~clk; integer c;
  initial begin m=512'h{msg:0128x};
    @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
    @(negedge clk) start=1; @(negedge clk) start=0;
    c=0; while(!done && c<400) begin @(negedge clk); c=c+1; end
    $display("D %064h", dig); $finish; end endmodule
"""
def rtl_digest(m_in):
    with tempfile.TemporaryDirectory() as d:
        tbp,outp=os.path.join(d,"tb.v"),os.path.join(d,"sim")
        open(tbp,"w").write(TB.format(msg=m_in))
        c=subprocess.run(["iverilog","-g2012","-o",outp,os.path.join(SRC,"blake3_anchor_v3.v"),tbp],
                         capture_output=True,text=True)
        if c.returncode: print("iverilog FAILED:\n"+c.stderr); sys.exit(2)
        out=subprocess.run(["vvp",outp],capture_output=True,text=True).stdout
        for l in out.splitlines():
            if l.startswith("D "): return int(l.split()[1],16)
    return None

def main():
    tests=[[(0x11111111*(i+1))&M for i in range(16)]] + \
          [[random.randint(0,M) for _ in range(16)] for _ in range(5)]
    full_ok = diff_v2 = True
    for mw in tests:
        m_in=pack(mw)
        rtl=rtl_digest(m_in)
        full=pack(model(mw, rounds=7, permute=True))    # Wave-5 reference
        v2  =pack(model(mw, rounds=4, permute=False))   # old reduced model
        if rtl != full: full_ok=False
        if rtl == v2:   diff_v2=False                   # must NOT equal the reduced one
    print("blake3_anchor_v3 == real 7-round + permuted BLAKE3-G model:", full_ok)
    print("blake3_anchor_v3 != reduced 4-round/no-perm v2 model:      ", diff_v2)
    ok = full_ok and diff_v2
    print("RESULT:", "WAVE-5 FULL-ROUND BLAKE3 VERIFIED" if ok else "MISMATCH")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
