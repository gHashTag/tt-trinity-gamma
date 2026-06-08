#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Verify blake3_anchor_v4 == the reference BLAKE3 compression function over random
# (chaining value, message, counter, block_len, flags). This is the full BLAKE3
# compress() primitive (keyed/tree-capable): state[0..7]=cv, state[8..11]=IV,
# state[12..15]=t0,t1,block_len,flags; 7 rounds + permutation; output
# out[i]=state[i]^state[i+8], out[i+8]=state[i+8]^cv[i].
import os, subprocess, sys, tempfile, random
random.seed(7)
HERE=os.path.dirname(os.path.abspath(__file__)); SRC=os.path.join(HERE,"..","src")
M=0xFFFFFFFF
IV=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
PERM=[2,6,3,10,7,0,4,13,1,11,12,5,9,14,15,8]
def rotr(x,n): return ((x>>n)|(x<<(32-n)))&M
def g(s,a,b,c,d,mx,my):
    s[a]=(s[a]+s[b]+mx)&M; s[d]=rotr(s[d]^s[a],16)
    s[c]=(s[c]+s[d])&M;    s[b]=rotr(s[b]^s[c],12)
    s[a]=(s[a]+s[b]+my)&M; s[d]=rotr(s[d]^s[a],8)
    s[c]=(s[c]+s[d])&M;    s[b]=rotr(s[b]^s[c],7)
def compress(cv, block, counter, block_len, flags):
    s = cv[:8] + IV[:4] + [counter&M, (counter>>32)&M, block_len&M, flags&M]
    m = list(block)
    for _ in range(7):
        g(s,0,4,8,12,m[0],m[1]);  g(s,1,5,9,13,m[2],m[3])
        g(s,2,6,10,14,m[4],m[5]); g(s,3,7,11,15,m[6],m[7])
        g(s,0,5,10,15,m[8],m[9]); g(s,1,6,11,12,m[10],m[11])
        g(s,2,7,8,13,m[12],m[13]);g(s,3,4,9,14,m[14],m[15])
        m=[m[PERM[i]] for i in range(16)]
    for i in range(8):
        s[i]^=s[i+8]; s[i+8]^=cv[i]
    return s   # 16 words
def pk(words):
    r=0
    for i,w in enumerate(words): r|=(w&M)<<(32*i)
    return r

TB="""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,start=0; reg [511:0] m; reg [255:0] cv; reg [63:0] ctr;
  reg [31:0] blen,fl; wire done; wire [255:0] dig; wire [511:0] full; wire ok;
  blake3_anchor_v4 u(.clk(clk),.rst_n(rst_n),.start(start),.m_in(m),.cv_in(cv),.counter(ctr),
    .block_len(blen),.flags(fl),.done(done),.digest(dig),.out_full(full),.hash_ok(ok));
  always #5 clk=~clk; integer c;
  initial begin
    m=512'h{m:0128x}; cv=256'h{cv:064x}; ctr=64'h{ctr:016x}; blen=32'h{blen:08x}; fl=32'h{fl:08x};
    @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
    @(negedge clk) start=1; @(negedge clk) start=0;
    c=0; while(!done && c<400) begin @(negedge clk); c=c+1; end
    $display("D %064h", dig); $display("F %0128h", full); $finish; end endmodule
"""
def rtl(mw, cvw, ctr, blen, fl):
    with tempfile.TemporaryDirectory() as d:
        open(d+"/tb.v","w").write(TB.format(m=pk(mw),cv=pk(cvw),ctr=ctr,blen=blen,fl=fl))
        c=subprocess.run(["iverilog","-g2012","-o",d+"/x",os.path.join(SRC,"blake3_anchor_v4.v"),d+"/tb.v"],
                         capture_output=True,text=True)
        if c.returncode: print("iverilog FAILED:\n"+c.stderr); sys.exit(2)
        out=subprocess.run(["vvp",d+"/x"],capture_output=True,text=True).stdout
        dg=fu=None
        for l in out.splitlines():
            if l.startswith("D "): dg=int(l.split()[1],16)
            if l.startswith("F "): fu=int(l.split()[1],16)
        return dg,fu

def main():
    dig_ok=full_ok=True
    cases=[(([0]*16),(IV[:8]),0,64,11)]   # IV cv, root-ish flags
    for _ in range(6):
        cases.append(([random.randint(0,M) for _ in range(16)],
                      [random.randint(0,M) for _ in range(8)],
                      random.randint(0,(1<<64)-1), random.randint(0,64), random.randint(0,255)))
    for mw,cvw,ctr,blen,fl in cases:
        s=compress(cvw, mw, ctr, blen, fl)
        ref_dig=pk(s[0:8]); ref_full=pk(s[0:16])
        dg,fu=rtl(mw,cvw,ctr,blen,fl)
        if dg!=ref_dig: dig_ok=False
        if fu!=ref_full: full_ok=False
    print("blake3_anchor_v4 digest (next CV) == reference compress()[0:8]:", dig_ok)
    print("blake3_anchor_v4 out_full (16 words) == reference compress():   ", full_ok)
    ok=dig_ok and full_ok
    print("RESULT:", "FULL BLAKE3 COMPRESSION VERIFIED (keyed/tree-capable)" if ok else "MISMATCH")
    return 0 if ok else 1

if __name__=="__main__":
    sys.exit(main())
