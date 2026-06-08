#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Verify blake3_hash_chunk (single-chunk BLAKE3, <=1024 bytes) against a reference
# single-chunk BLAKE3 that is itself validated against the OFFICIAL BLAKE3 test
# vectors (input byte i = i % 251). Drives the RTL FSM over many message lengths
# (block boundaries, partials, full chunk) and compares the 256-bit hash.
import os, subprocess, sys, tempfile
HERE=os.path.dirname(os.path.abspath(__file__)); SRC=os.path.join(HERE,"..","src")
M=0xFFFFFFFF
IV=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
PERM=[2,6,3,10,7,0,4,13,1,11,12,5,9,14,15,8]
CS,CE,RT=1,2,8
def rotr(x,n): return ((x>>n)|(x<<(32-n)))&M
def g(s,a,b,c,d,mx,my):
    s[a]=(s[a]+s[b]+mx)&M;s[d]=rotr(s[d]^s[a],16);s[c]=(s[c]+s[d])&M;s[b]=rotr(s[b]^s[c],12)
    s[a]=(s[a]+s[b]+my)&M;s[d]=rotr(s[d]^s[a],8); s[c]=(s[c]+s[d])&M;s[b]=rotr(s[b]^s[c],7)
def compress(cv,blk,ctr,blen,fl):
    s=cv[:8]+IV[:4]+[ctr&M,(ctr>>32)&M,blen&M,fl&M]; m=list(blk)
    for _ in range(7):
        g(s,0,4,8,12,m[0],m[1]);g(s,1,5,9,13,m[2],m[3]);g(s,2,6,10,14,m[4],m[5]);g(s,3,7,11,15,m[6],m[7])
        g(s,0,5,10,15,m[8],m[9]);g(s,1,6,11,12,m[10],m[11]);g(s,2,7,8,13,m[12],m[13]);g(s,3,4,9,14,m[14],m[15])
        m=[m[PERM[i]] for i in range(16)]
    for i in range(8): s[i]^=s[i+8]; s[i+8]^=cv[i]
    return s
def words(b): b=b+bytes(64-len(b)); return [int.from_bytes(b[4*i:4*i+4],'little') for i in range(16)]
def ref_words(data):
    blocks=[data[i:i+64] for i in range(0,len(data),64)] or [b'']
    n=len(blocks); cv=IV[:8]
    for i,bl in enumerate(blocks):
        fl=(CS if i==0 else 0)|((CE|RT) if i==n-1 else 0)
        cv=compress(cv,words(bl),0,len(bl),fl)[0:8]
    return cv                                            # 8 chaining-value words
def ref(data):  # official-vector form: word0-first, little-endian bytes
    return b''.join(w.to_bytes(4,'little') for w in ref_words(data))
def ref_int(data):  # RTL hash int form: word0 in the low 32 bits (= v4 digest packing)
    r=0
    for i,w in enumerate(ref_words(data)): r|=w<<(32*i)
    return r

# official vector self-check (so the reference is trusted)
def tinp(n): return bytes(i%251 for i in range(n))
OFFICIAL={0:"af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262",
          1:"2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213",
          1024:"42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"}

TB="""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,start=0; reg [8191:0] msg; reg [10:0] len; wire done; wire [255:0] h; wire ok;
  blake3_hash_chunk u(.clk(clk),.rst_n(rst_n),.start(start),.msg(msg),.msg_len(len),.done(done),.hash(h),.hash_ok(ok));
  always #5 clk=~clk; integer c;
  initial begin msg=8192'h{msg:02048x}; len=11'd{n};
    @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
    @(negedge clk) start=1; @(negedge clk) start=0;
    c=0; while(!done && c<3000) begin @(negedge clk); c=c+1; end
    $display("H %064h", h); $finish; end endmodule
"""
def rtl(data):
    buf=data+bytes(1024-len(data))          # zero-pad to 1024 bytes (as the spec does)
    msg_int=int.from_bytes(buf,'little')    # word0 in low bits (LE)
    with tempfile.TemporaryDirectory() as d:
        open(d+"/tb.v","w").write(TB.format(msg=msg_int,n=len(data)))
        c=subprocess.run(["iverilog","-g2012","-o",d+"/x",os.path.join(SRC,"blake3_hash_chunk.v"),d+"/tb.v"],
                         capture_output=True,text=True)
        if c.returncode: print("iverilog FAILED:\n"+c.stderr); sys.exit(2)
        out=subprocess.run(["vvp",d+"/x"],capture_output=True,text=True).stdout
        for l in out.splitlines():
            if l.startswith("H "):
                return int(l.split()[1],16)          # word0 in low 32 bits
    return None

def main():
    # 1) trust the reference
    for n,exp in OFFICIAL.items():
        assert ref(tinp(n)).hex()==exp, f"reference FAILS official vector len {n}"
    print("reference validated against official BLAKE3 vectors (len 0/1/1024): OK")
    # 2) RTL vs reference over many lengths
    lens=[0,1,2,63,64,65,100,127,128,129,200,255,256,512,700,960,1000,1023,1024]
    bad=0
    for n in lens:
        data=tinp(n)
        r=rtl(data); e=ref_int(data)
        if r!=e: bad+=1; print(f"  len {n}: MISMATCH rtl={r:064x} ref={e:064x}")
    print(f"RTL vs reference: {len(lens)-bad}/{len(lens)} lengths match")
    ok=bad==0
    print("RESULT:", "SINGLE-CHUNK BLAKE3 HASH VERIFIED (official-vector-anchored)" if ok else "MISMATCH")
    return 0 if ok else 1

if __name__=="__main__":
    sys.exit(main())
