#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Verify blake3_keyed_hash (keyed BLAKE3 MAC, <=4096 bytes) == blake3.blake3(data,
# key=key) over many lengths. Keyed mode = key replaces IV as the chunk/parent CV +
# KEYED_HASH flag on every compression.
import os, subprocess, sys, tempfile
try:
    import blake3
except Exception as e:
    print("SKIP: needs the blake3 package (", e, ")"); sys.exit(0)
HERE=os.path.dirname(os.path.abspath(__file__)); SRC=os.path.join(HERE,"..","src")
TB="""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,start=0; reg [32767:0] msg; reg [12:0] len; reg [255:0] key;
  wire done; wire [255:0] h; wire ok;
  blake3_keyed_hash u(.clk(clk),.rst_n(rst_n),.start(start),.msg(msg),.msg_len(len),.key_in(key),
    .done(done),.hash(h),.hash_ok(ok));
  always #5 clk=~clk; integer c;
  initial begin msg=32768'h{msg:08192x}; len=13'd{n}; key=256'h{key:064x};
    @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
    @(negedge clk) start=1; @(negedge clk) start=0;
    c=0; while(!done && c<20000) begin @(negedge clk); c=c+1; end
    $display("H %064h", h); $finish; end endmodule
"""
def rtl(data, key):
    buf=data+bytes(4096-len(data)); msg_int=int.from_bytes(buf,'little')
    key_int=int.from_bytes(key,'little')   # word0 in low bits
    with tempfile.TemporaryDirectory() as d:
        open(d+"/tb.v","w").write(TB.format(msg=msg_int,n=len(data),key=key_int))
        c=subprocess.run(["iverilog","-g2012","-o",d+"/x",os.path.join(SRC,"blake3_keyed_hash.v"),d+"/tb.v"],
                         capture_output=True,text=True)
        if c.returncode: print("iverilog FAILED:\n"+c.stderr); sys.exit(2)
        out=subprocess.run(["vvp",d+"/x"],capture_output=True,text=True).stdout
        for l in out.splitlines():
            if l.startswith("H "):
                hx=int(l.split()[1],16)
                return b''.join(((hx>>(32*i))&0xffffffff).to_bytes(4,'little') for i in range(8))
    return None
def main():
    key=bytes((i*5+1)%256 for i in range(32))         # deterministic 32-byte key
    lens=[0,1,64,100,1024,1025,2048,3000,3072,4096]
    bad=0
    for n in lens:
        data=bytes((i*7+3)%251 for i in range(n))
        r=rtl(data,key); e=blake3.blake3(data,key=key).digest()
        if r!=e: bad+=1; print(f"  len {n:5d}: MISMATCH rtl={r.hex()[:24]} pkg={e.hex()[:24]}")
        else:    print(f"  len {n:5d}: MATCH")
    print(f"\nRTL vs blake3(key=) : {len(lens)-bad}/{len(lens)} lengths match")
    print("RESULT:", "KEYED BLAKE3 (MAC) VERIFIED vs blake3 package" if bad==0 else "MISMATCH")
    return 0 if bad==0 else 1
if __name__=="__main__":
    sys.exit(main())
