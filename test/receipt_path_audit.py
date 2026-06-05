#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Receipt / identity / nonce-path conformance audit.
#
# After three active-silicon defects were found by checking instantiated RTL
# against the algorithm it claims to implement (gf16_mul rounding-overflow,
# bitnet neuron aliasing, blake3_anchor missing-XOR), this script audits the
# OTHER instantiated primitives on the same receipt / die-identity / nonce path
# against their clean references, to bound the defect search:
#
#   crc32_receipt  -- CRC-32 (IEEE 802.3) vs zlib + the canonical 0xCBF43926
#   lucas_rom      -- L2..L7 ROM vs the Lucas sequence
#   hwrng_lfsr     -- 16-bit nonce LFSR: period must be maximal (65535) and the
#                     cycle must visit every nonzero state once; RTL == model
#   cassini_post   -- Cassini-Lucas POST self-checker: passes clean AND detects
#                     a corrupted Lucas value (a live checker, not a vacuous pass)
#
# Result of the 2026-06 run: ALL FOUR CORRECT on Gamma and Euler. The only
# defect on this path is blake3_anchor (see blake3_anchor_verify.py).
import os, subprocess, tempfile, zlib, random, sys
random.seed(5)
HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")

def sim(src_files, tb_text, tag):
    d = tempfile.mkdtemp(); tbp = os.path.join(d, "tb.v")
    open(tbp, "w").write(tb_text)
    files = [os.path.join(SRC, f) for f in src_files] + [tbp]
    c = subprocess.run(["iverilog", "-g2012", "-o", d+"/x", *files],
                       capture_output=True, text=True)
    if c.returncode:
        print(f"{tag}: COMPILE FAIL\n{c.stderr[:300]}"); sys.exit(2)
    return subprocess.run(["vvp", d+"/x"], capture_output=True, text=True).stdout

def grab(out, pfx):
    return [l[len(pfx):].strip() for l in out.splitlines() if l.startswith(pfx)]

# ---------------------------------------------------------------- crc32_receipt
def audit_crc32():
    def rtl(data):
        feed = "".join(f"      @(negedge clk) begin valid=1; byte_in=8'h{b:02x}; end\n"
                       for b in data)
        tb = f"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,start=0,valid=0; reg [7:0] byte_in; wire [31:0] raw,fin;
 crc32_receipt u(.clk(clk),.rst_n(rst_n),.start(start),.valid(valid),
                 .byte_in(byte_in),.crc_raw(raw),.crc_final(fin));
 always #5 clk=~clk;
 initial begin @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
  @(negedge clk) start=1; @(negedge clk) start=0;
{feed}      @(negedge clk) valid=0; #1 $display("C %08h", fin); $finish; end endmodule"""
        return int(grab(sim(["crc32_receipt.v"], tb, "crc32"), "C ")[0], 16)
    chk = rtl(list(b"123456789")); canon = 0xCBF43926
    bad = sum(1 for _ in range(40)
              if (lambda m: rtl(m) != (zlib.crc32(bytes(m)) & 0xFFFFFFFF))
                 ([random.randint(0,255) for _ in range(random.randint(1,20))]))
    ok = (chk == canon) and bad == 0
    print(f"crc32_receipt : canonical 0x{chk:08x}==0xCBF43926 {chk==canon}; "
          f"40 random vs zlib {40-bad}/40  -> {'OK' if ok else 'FAIL'}")
    return ok

# ------------------------------------------------------------------- lucas_rom
def audit_lucas():
    L = [0,1,3,4,7,11,18,29]  # L0..L7
    tb = """`timescale 1ns/1ps
module tb; reg [2:0] idx; wire [7:0] v; lucas_rom u(.idx(idx),.value(v));
 integer i; initial begin for(i=0;i<6;i=i+1) begin idx=i[2:0]; #1 $display("L %0d %0d", i, v); end $finish; end endmodule"""
    out = grab(sim(["lucas_rom.v"], tb, "lucas"), "L ")
    ok = all(int(v) == L[2+int(i)] for i, v in (p.split() for p in out))
    print(f"lucas_rom     : L2..L7 == Lucas sequence {ok}")
    return ok

# ------------------------------------------------------------------ hwrng_lfsr
def audit_lfsr():
    def step(s):
        fb = ((s>>15)^(s>>13)^(s>>12)^(s>>10)) & 1
        return ((s<<1)|fb) & 0xFFFF
    s=0xACE1; cyc=set(); seq=[]
    for _ in range(65535): cyc.add(s); seq.append(s); s=step(s)
    maximal = (s == 0xACE1) and cyc == set(range(1,65536))
    tb = """`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,ena=0; wire [15:0] r;
 hwrng_lfsr u(.clk(clk),.rst_n(rst_n),.ena(ena),.rnd(r));
 always #5 clk=~clk; integer k;
 initial begin @(negedge clk) rst_n=0; @(negedge clk) rst_n=1; ena=1;
  $display("S %04h", r);
  for(k=0;k<23;k=k+1) begin @(negedge clk); $display("S %04h", r); end $finish; end endmodule"""
    rtl = [int(x,16) for x in grab(sim(["hwrng_lfsr.v"], tb, "lfsr"), "S ")]
    faithful = rtl == seq[:len(rtl)]
    ok = maximal and faithful
    print(f"hwrng_lfsr    : period 65535 & visits all nonzero {maximal}; "
          f"RTL faithful {faithful}  -> {'OK' if ok else 'FAIL'}")
    return ok

# ----------------------------------------------------------------- cassini_post
def audit_cassini():
    src = open(os.path.join(SRC, "cassini_post.v")).read()
    tb = """`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0; wire ok,dn;
 cassini_post u(.clk(clk),.rst_n(rst_n),.cassini_ok(ok),.post_done(dn));
 always #5 clk=~clk; integer k;
 initial begin @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
  for(k=0;k<12 && !dn;k=k+1) @(negedge clk); #1 $display("R %b %b", ok, dn); $finish; end endmodule"""
    def runsrc(text):
        d=tempfile.mkdtemp(); sp=d+"/m.v"; open(sp,"w").write(text); open(d+"/tb.v","w").write(tb)
        c=subprocess.run(["iverilog","-g2012","-o",d+"/x",sp,d+"/tb.v"],capture_output=True,text=True)
        if c.returncode: print("cassini COMPILE FAIL",c.stderr[:200]); sys.exit(2)
        return grab(subprocess.run(["vvp",d+"/x"],capture_output=True,text=True).stdout, "R ")[0]
    happy = runsrc(src) == "1 1"
    # inject a fault into whichever form this die uses (`*` form or LUT form)
    if "lhs_lut = 10'd77" in src:
        fault = src.replace("4'd4:    lhs_lut = 10'd77;", "4'd4:    lhs_lut = 10'd78;")
    else:
        fault = src.replace("4'd4: lucas = 8'd7;", "4'd4: lucas = 8'd8;")
    detected = runsrc(fault).startswith("0")
    ok = happy and detected
    print(f"cassini_post  : passes clean {happy}; detects corrupted Lucas {detected} "
          f"(live checker)  -> {'OK' if ok else 'FAIL'}")
    return ok

def main():
    print("== receipt / identity / nonce-path conformance audit ==")
    results = [audit_crc32(), audit_lucas(), audit_lfsr(), audit_cassini()]
    allok = all(results)
    print("RESULT:", "ALL FOUR PRIMITIVES CORRECT (only blake3_anchor on this path is broken)"
          if allok else "DEFECT FOUND")
    return 0 if allok else 1

if __name__ == "__main__":
    sys.exit(main())
