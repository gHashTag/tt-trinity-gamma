#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Verify blake3_hash (multi-chunk BLAKE3 tree, <=4096 bytes) against the reference
# `blake3` package over many lengths (single chunk, partial, power-of-2 and odd chunk
# counts, block boundaries). This is the full BLAKE3 hash for messages up to 4 chunks.
import os, subprocess, sys, tempfile
try:
    import blake3
except Exception as e:
    print("SKIP: needs the blake3 package (", e, ")"); sys.exit(0)
HERE=os.path.dirname(os.path.abspath(__file__)); SRC=os.path.join(HERE,"..","src")
DEPS=["blake3_hash.v"]
TB="""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,start=0; reg [32767:0] msg; reg [12:0] len; wire done; wire [255:0] h; wire ok;
  blake3_hash u(.clk(clk),.rst_n(rst_n),.start(start),.msg(msg),.msg_len(len),.done(done),.hash(h),.hash_ok(ok));
  always #5 clk=~clk; integer c;
  initial begin msg=32768'h{msg:08192x}; len=13'd{n};
    @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
    @(negedge clk) start=1; @(negedge clk) start=0;
    c=0; while(!done && c<20000) begin @(negedge clk); c=c+1; end
    $display("H %064h", h); $finish; end endmodule
"""
def rtl(data):
    buf=data+bytes(4096-len(data))
    msg_int=int.from_bytes(buf,'little')
    with tempfile.TemporaryDirectory() as d:
        open(d+"/tb.v","w").write(TB.format(msg=msg_int,n=len(data)))
        c=subprocess.run(["iverilog","-g2012","-o",d+"/x",*[os.path.join(SRC,s) for s in DEPS],d+"/tb.v"],
                         capture_output=True,text=True)
        if c.returncode: print("iverilog FAILED:\n"+c.stderr); sys.exit(2)
        out=subprocess.run(["vvp",d+"/x"],capture_output=True,text=True).stdout
        for l in out.splitlines():
            if l.startswith("H "):
                hx=int(l.split()[1],16)
                return b''.join(((hx>>(32*i))&0xffffffff).to_bytes(4,'little') for i in range(8))
    return None

def main():
    lens=[0,1,64,100,1023,1024,1025,1536,2000,2048,2049,3000,3072,3073,4000,4095,4096]
    bad=0
    for n in lens:
        data=bytes((i*7+3)%251 for i in range(n))   # deterministic test pattern
        r=rtl(data); e=blake3.blake3(data).digest()
        nch=(n+1023)//1024 or 1
        if r!=e: bad+=1; print(f"  len {n:5d} ({nch} ch): MISMATCH rtl={r.hex()[:24]} pkg={e.hex()[:24]}")
        else:    print(f"  len {n:5d} ({nch} ch): MATCH")
    print(f"\nRTL vs blake3 package: {len(lens)-bad}/{len(lens)} lengths match")
    print("RESULT:", "MULTI-CHUNK BLAKE3 TREE VERIFIED (vs blake3 package)" if bad==0 else "MISMATCH")
    return 0 if bad==0 else 1

if __name__=="__main__":
    sys.exit(main())
