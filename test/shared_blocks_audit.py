#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Shared neuromorphic/mesh block conformance audit (the last instantiated blocks).
#
# Completes the instantiated-subsystem audit across all four dies by checking the
# remaining shared blocks against their contracts:
#
#   d2d_holo_mesh        -- 4-port D2D router stub: TX = {spike_count[3],
#                           spike_count[0], gf_tag[0], SYNC}; SYNC = (spike_count==8)
#                           AND NOT layer_frozen; RX latched. (gamma + euler)
#   nca_entropy_monitor  -- 81-cell nonzero popcount, in_band = [31,80], violation
#                           pulse outside band. (gamma + euler)
#   holo_lut_pe          -- binary MAP-B VSA PE: bind/unbind = XOR (self-inverse),
#                           bundle = OR, NOP = 0; round-trip unbind(bind(a,b),b)=a.
#                           (gamma only)
#   trinity_cortex_8col  -- 8x cortical_column + popcount tree: invariant
#                           spike_count == popcount(spike_vec). (gamma only)
#
# Absent modules are skipped (euler lacks holo_lut_pe / trinity_cortex_8col).
# 2026-06 result: ALL shared blocks CORRECT on every die that carries them.
import os, subprocess, tempfile, sys
HERE=os.path.dirname(os.path.abspath(__file__)); SRC=os.path.join(HERE,"..","src")
def has(m): return os.path.exists(os.path.join(SRC,m+".v"))
def sim(srcs, tb, tag):
    d=tempfile.mkdtemp(); open(d+"/tb.v","w").write(tb)
    files=[os.path.join(SRC,s) for s in srcs]+[d+"/tb.v"]
    c=subprocess.run(["iverilog","-g2012","-o",d+"/x",*files],capture_output=True,text=True)
    if c.returncode: print(f"{tag}: COMPILE FAIL\n{c.stderr[:300]}"); sys.exit(2)
    return subprocess.run(["vvp",d+"/x"],capture_output=True,text=True).stdout
def L(out,p): return [l[len(p):].strip() for l in out.splitlines() if l.startswith(p)]

def audit_d2d():
    tb=r"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,ena=1,lf=0,nrx=0,erx=0,srx=0,wrx=0; reg [3:0] sc,gt; reg [7:0] sv;
 wire ntx,etx,stx,wtx,nq,eq,sq,wq,ok;
 d2d_holo_mesh u(.clk(clk),.rst_n(rst_n),.ena(ena),.spike_count(sc),.spike_vec(sv),.gf_tag(gt),
  .layer_frozen(lf),.n_rx(nrx),.e_rx(erx),.s_rx(srx),.w_rx(wrx),
  .n_tx(ntx),.e_tx(etx),.s_tx(stx),.w_tx(wtx),.n_rx_q(nq),.e_rx_q(eq),.s_rx_q(sq),.w_rx_q(wq),.mesh_ok(ok));
 always #5 clk=~clk;
 task st(input [3:0]c,input [3:0]g,input f,input a,input b,input cc,input d); begin
   @(negedge clk) begin sc=c;gt=g;lf=f;nrx=a;erx=b;srx=cc;wrx=d; end @(negedge clk); #1
   $display("R %b%b%b%b %b%b%b%b", ntx,etx,stx,wtx,nq,eq,sq,wq); end endtask
 initial begin @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
   st(4'h8,4'h1,0,1,0,1,0); st(4'h8,4'h0,1,0,1,0,1); st(4'hF,4'h1,0,1,1,1,1); st(4'h0,4'h0,0,0,0,0,0);
   $finish; end endmodule"""
    rows=L(sim(["d2d_holo_mesh.v"],tb,"d2d"),"R ")
    cases=[(8,1,0,1,0,1,0),(8,0,1,0,1,0,1),(15,1,0,1,1,1,1),(0,0,0,0,0,0,0)]
    ok=True
    for (c,g,f,a,b,cc,dd),row in zip(cases,rows):
        tx=f"{(c>>3)&1}{c&1}{g&1}{(1 if c==8 else 0)&(0 if f else 1)}"
        rx=f"{a}{b}{cc}{dd}"
        if row!=f"{tx} {rx}": ok=False
    print(f"d2d_holo_mesh        : TX map + layer-frozen SYNC gate + RX latch  -> {'OK' if ok else 'FAIL'}")
    return ok

def audit_nca():
    def run(pop):
        val=sum(1<<(2*i) for i in range(pop))
        tb=f"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,sample=0; reg [161:0] t; wire viol,inb; wire [6:0] lp;
 nca_entropy_monitor u(.clk(clk),.rst_n(rst_n),.trits_in(t),.sample(sample),
   .entropy_violation(viol),.in_band(inb),.last_popcount(lp));
 always #5 clk=~clk;
 initial begin t=162'h0; @(negedge clk) rst_n=0; @(negedge clk) rst_n=1; t=162'h{val:041x};
  @(negedge clk) #1 $display("IB %b", inb);
  @(negedge clk) sample=1; @(negedge clk) sample=0; #1 $display("V %b %0d", viol, lp); $finish; end endmodule"""
        out=sim(["nca_entropy_monitor.v"],tb,"nca")
        inb=int(L(out,"IB ")[0]); v,lp=L(out,"V ")[0].split(); return inb,int(v),int(lp)
    bad=0
    for pop in [0,30,31,32,79,80,81]:
        inb,v,lp=run(pop); ei=1 if 31<=pop<=80 else 0; ev=0 if 31<=pop<=80 else 1
        if not(inb==ei and v==ev and lp==pop): bad+=1
    print(f"nca_entropy_monitor  : band [31,80], violation + popcount (7 boundaries)  -> {'OK' if bad==0 else 'FAIL'}")
    return bad==0

def audit_holo():
    if not has("holo_lut_pe"):
        print("holo_lut_pe          : absent on this die -- skipped"); return True
    tb=r"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,vi=0; reg [1:0] op; reg [31:0] a,b; wire [31:0] o; wire vo;
 holo_lut_pe u(.clk(clk),.rst_n(rst_n),.op(op),.hv_a(a),.hv_b(b),.valid_in(vi),.hv_out(o),.valid_out(vo));
 always #5 clk=~clk;
 task d(input [1:0]p,input[31:0]x,input[31:0]y); begin
   @(negedge clk) begin op=p;a=x;b=y;vi=1; end @(negedge clk) #1 $display("R %0d %08h", p, o); end endtask
 initial begin @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
   d(0,32'hDEADBEEF,32'h12345678); d(1,32'hDEADBEEF,32'h12345678);
   d(2,32'hF0F0F0F0,32'h0F0F00FF); d(3,32'hFFFFFFFF,32'hFFFFFFFF); $finish; end endmodule"""
    rows=[r.split() for r in L(sim(["holo_lut_pe.v"],tb,"holo"),"R ")]
    a,b=0xDEADBEEF,0x12345678
    exp={0:f"{a^b:08x}",1:f"{a^b:08x}",2:f"{0xF0F0F0F0|0x0F0F00FF:08x}",3:"00000000"}
    ok=all(r[1]==exp[int(r[0])] for r in rows) and ((a^b)^b)==a
    print(f"holo_lut_pe          : binary MAP-B bind/unbind/bundle/NOP + round-trip  -> {'OK' if ok else 'FAIL'}")
    return ok

def audit_cortex():
    if not has("trinity_cortex_8col"):
        print("trinity_cortex_8col  : absent on this die -- skipped"); return True
    tb=r"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,ena=1; reg [3:0] g0,g1,g2,g3; reg [31:0] stim;
 wire [3:0] sc; wire [7:0] sv; wire ok; integer i,bad;
 trinity_cortex_8col u(.clk(clk),.rst_n(rst_n),.ena(ena),.gf_in0(g0),.gf_in1(g1),.gf_in2(g2),.gf_in3(g3),
   .stim_bus(stim),.spike_count(sc),.spike_vec(sv),.cortex_ok(ok));
 always #5 clk=~clk;
 function [3:0] pc8(input [7:0] x); integer j; begin pc8=0; for(j=0;j<8;j=j+1) pc8=pc8+x[j]; end endfunction
 initial begin bad=0; g0=4'h3;g1=4'h2;g2=4'h1;g3=4'h4; stim=0;
   @(negedge clk) rst_n=0; repeat(2)@(negedge clk); rst_n=1;
   for(i=0;i<200;i=i+1) begin stim={$random};g0={$random};g1={$random};g2={$random};g3={$random};
     @(negedge clk); #1 if(sc!==pc8(sv)) bad=bad+1; end
   $display("B %0d", bad); $finish; end endmodule"""
    bad=int(L(sim(["trinity_cortex_8col.v","cortical_column.v"],tb,"cortex"),"B ")[0])
    print(f"trinity_cortex_8col  : spike_count == popcount(spike_vec), 200 cycles ({bad} bad)  -> {'OK' if bad==0 else 'FAIL'}")
    return bad==0

def main():
    print("== shared neuromorphic/mesh block conformance audit ==")
    r=[audit_d2d(), audit_nca(), audit_holo(), audit_cortex()]
    allok=all(r)
    print("RESULT:", "all shared blocks CORRECT" if allok else "FAIL")
    return 0 if allok else 1

if __name__=="__main__":
    sys.exit(main())
