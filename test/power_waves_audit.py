#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Power/sparsity wave (39-42) conformance audit -- dead-code library units checked
# against their stated contracts (none are instantiated on a die top).
#
#   sparse_skip (Wave-40): skip_count == popcount(sparse_mask); when over threshold,
#                          active_lanes == ~sparse_mask (zero-skip equivalence).
#                          CORRECT. (Minor: opcode port [3:0] cannot hold the
#                          contract opcode 0xE1 -- works only via truncation to 0x1.)
#   stoch_round (Wave-41): claims P(round up) = fractional part, but rounds up with
#                          prob 0.5 only when LSB=1 (=> NOT stochastic rounding).
#   stoch_round_v2:        true stochastic rounding -- P(round up) = frac/256, so the
#                          mean carry == frac/256 (unbiased). Verified statistically.
import os, subprocess, tempfile, sys
HERE = os.path.dirname(os.path.abspath(__file__)); SRC = os.path.join(HERE, "..", "src")
def sim(src, tb, tag):
    d=tempfile.mkdtemp(); open(d+"/tb.v","w").write(tb)
    c=subprocess.run(["iverilog","-g2012","-o",d+"/x",os.path.join(SRC,src),d+"/tb.v"],capture_output=True,text=True)
    if c.returncode: print(f"{tag}: COMPILE FAIL\n{c.stderr[:300]}"); sys.exit(2)
    return subprocess.run(["vvp",d+"/x"],capture_output=True,text=True).stdout

def audit_sparse_skip():
    tb=r"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0; reg [3:0] op; reg [15:0] sm,cm; reg [7:0] th;
 wire [15:0] al; wire [7:0] sc,eff; wire skm;
 sparse_skip u(.clk(clk),.rst_n(rst_n),.opcode(op),.sparse_mask(sm),.compute_mask(cm),
   .threshold(th),.active_lanes(al),.skip_count(sc),.efficiency(eff),.skip_mode(skm));
 always #5 clk=~clk;
 task t(input [15:0] mask); begin sm=mask; @(negedge clk); @(negedge clk); #1
   $display("R %04h %0d %04h", mask, sc, al); end endtask
 initial begin op=4'd1; cm=16'hFFFF; th=8'd1;
  @(negedge clk) rst_n=0; @(negedge clk) rst_n=1; @(negedge clk);
  t(16'h0000); t(16'h00FF); t(16'hAAAA); t(16'hFFFF); t(16'h0001); t(16'h8001); $finish; end endmodule"""
    bad=0
    for l in sim("sparse_skip.v",tb,"sparse").splitlines():
        if not l.startswith("R "): continue
        mask,sc,al=l.split()[1:]; mask=int(mask,16); sc=int(sc); al=int(al,16)
        pc=bin(mask).count("1"); exp=(~mask)&0xFFFF
        if not (sc==pc and (al==exp if pc>=1 else al==0xFFFF)): bad+=1
    print(f"sparse_skip  : skip_count==popcount & active==~sparse_mask  -> {'OK' if bad==0 else 'FAIL'}")
    return bad==0

def round_prob(mod, frac, lsb, n=2048):
    """measure P(round up) over n cycles for the given module."""
    if mod=="stoch_round":
        tb=f"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0; reg [7:0] op; reg [15:0] din,seed; wire [15:0] dout; wire v;
 stoch_round u(.clk(clk),.reset_n(rst_n),.opcode(op),.data_in(din),.random_seed(seed),.data_out(dout),.valid(v));
 always #5 clk=~clk; integer i,up;
 initial begin op=8'hE9; seed=16'h1234; up=0; din=16'h40{lsb:02x};
  @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
  for(i=0;i<{n};i=i+1) begin @(negedge clk); if(dout!=din) up=up+1; end
  $display("U %0d", up); $finish; end endmodule"""
        src="stoch_round.v"
    else:
        tb=f"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,ena=1; reg [15:0] val; reg [7:0] fr; wire [15:0] res; wire v;
 stoch_round_v2 u(.clk(clk),.reset_n(rst_n),.ena(ena),.value(val),.frac(fr),.result(res),.valid(v));
 always #5 clk=~clk; integer i,up;
 initial begin val=16'h4000; fr=8'd{frac}; up=0;
  @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
  for(i=0;i<{n};i=i+1) begin @(negedge clk); if(res!=val) up=up+1; end
  $display("U %0d", up); $finish; end endmodule"""
        src="stoch_round_v2.v"
    out=sim(src,tb,mod)
    return int([l for l in out.splitlines() if l.startswith("U ")][0].split()[1]), n

def audit_stoch():
    up1,n=round_prob("stoch_round",0,1); up0,_=round_prob("stoch_round",0,0)
    # shipped: ~0.5 when LSB=1, 0 when LSB=0 -> NOT prob=fractional-part
    shipped_wrong = (abs(up1/n-0.5)<0.1) and (up0==0)
    print(f"stoch_round  : P(up|LSB=1)={up1/n:.3f} P(up|LSB=0)={up0/n:.3f} "
          f"-> NOT stochastic rounding (prob=0.5*LSB) confirmed: {shipped_wrong}")
    # v2: P(round up) should == frac/256 for several fracs (unbiased)
    ok=True
    for frac in (0,64,128,192,255):
        up,n=round_prob("v2",frac,0)
        exp=frac/256.0; obs=up/n
        good = abs(obs-exp)<0.05
        ok &= good
        print(f"stoch_round_v2: frac={frac:3d} P(up)={obs:.3f} expect {exp:.3f}  {'ok' if good else 'BAD'}")
    print(f"stoch_round_v2: unbiased P(up)==frac/256  -> {'OK' if ok else 'FAIL'}")
    return shipped_wrong and ok

def main():
    print("== power/sparsity wave (39-42) audit -- dead-code library units ==")
    r=[audit_sparse_skip(), audit_stoch()]
    ok=all(r)
    print("RESULT:", "sparse_skip CORRECT; stoch_round defect characterized + v2 verified unbiased"
          if ok else "UNEXPECTED")
    return 0 if ok else 1

if __name__=="__main__":
    sys.exit(main())
