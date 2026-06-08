#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Power/sparsity wave (39-42) conformance audit -- dead-code library units checked
# against their stated contracts (none are instantiated on a die top).
#
#   sparse_skip (Wave-40): skip_count==popcount(sparse_mask), active_lanes==~sparse
#   stoch_round (Wave-41): NOT stochastic rounding (prob=0.5*LSB); stoch_round_v2 is
#                          the unbiased fix (P(up)=frac/256).
#   spec_exit  (Wave-39): exit_enable == (confidence >= threshold), flush==exit
#   null_pe    (Wave-40): power/clock gate == activate
#   dfs_gate   (Wave-40): skip == (depth>16 && !visited), skip_counter accumulates
#   subth_clk          : clk_freq == 2^divider
#   opcode-width gate  : every unit's opcode port is wide enough for its 8-bit
#                        "sacred opcode" (sparse_skip 0xE1 / subth_clk 0xE5 /
#                        fbb_active_path 0xF2 were [3:0] -- truncated to the low
#                        nibble -> opcode collision; widened to [7:0]).
import os, re, subprocess, tempfile, sys
HERE=os.path.dirname(os.path.abspath(__file__)); SRC=os.path.join(HERE,"..","src")
def sim(srcs, tb, tag):
    d=tempfile.mkdtemp(); open(d+"/tb.v","w").write(tb)
    files=[os.path.join(SRC,s) for s in srcs]+[d+"/tb.v"]
    c=subprocess.run(["iverilog","-g2012","-o",d+"/x",*files],capture_output=True,text=True)
    if c.returncode: print(f"{tag}: COMPILE FAIL\n{c.stderr[:300]}"); sys.exit(2)
    return subprocess.run(["vvp",d+"/x"],capture_output=True,text=True).stdout
def grab(o,p): return [l[len(p):].strip() for l in o.splitlines() if l.startswith(p)]

def audit_sparse_skip():
    tb=r"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0; reg [7:0] op; reg [15:0] sm,cm; reg [7:0] th;
 wire [15:0] al; wire [7:0] sc,eff; wire skm;
 sparse_skip u(.clk(clk),.rst_n(rst_n),.opcode(op),.sparse_mask(sm),.compute_mask(cm),
   .threshold(th),.active_lanes(al),.skip_count(sc),.efficiency(eff),.skip_mode(skm));
 always #5 clk=~clk;
 task t(input [15:0] m); begin sm=m; @(negedge clk); @(negedge clk); #1 $display("R %04h %0d %04h",m,sc,al); end endtask
 initial begin op=8'hE1; cm=16'hFFFF; th=8'd1; @(negedge clk) rst_n=0; @(negedge clk) rst_n=1; @(negedge clk);
  t(16'h00FF); t(16'hAAAA); t(16'hFFFF); t(16'h0001); $finish; end endmodule"""
    bad=0
    for l in grab(sim(["sparse_skip.v"],tb,"sparse"),"R "):
        m,sc,al=l.split(); m=int(m,16); sc=int(sc); al=int(al,16); pc=bin(m).count("1")
        if not (sc==pc and al==((~m)&0xFFFF)): bad+=1
    print(f"sparse_skip   : skip_count==popcount & active==~sparse  -> {'OK' if bad==0 else 'FAIL'}")
    return bad==0

def audit_spec_exit():
    tb=r"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0; reg [7:0] op; reg [15:0] c,t; wire ee,fe,v;
 spec_exit u(.clk(clk),.reset_n(rst_n),.opcode(op),.confidence(c),.threshold(t),.exit_enable(ee),.flush_enable(fe),.valid(v));
 always #5 clk=~clk;
 task k(input[15:0]cc,input[15:0]tt); begin @(negedge clk) begin op=8'hEB;c=cc;t=tt; end @(negedge clk) #1 $display("R %0d %b %b",(cc>=tt),ee,fe); end endtask
 initial begin @(negedge clk) rst_n=0; @(negedge clk) rst_n=1; k(100,50); k(50,100); k(50,50); k(0,1); $finish; end endmodule"""
    bad=0
    for l in grab(sim(["spec_exit.v"],tb,"spec"),"R "):
        exp,ee,fe=l.split(); ok=(ee==exp and fe==exp); bad+= 0 if ok else 1
    print(f"spec_exit     : exit_enable==(conf>=thresh), flush==exit  -> {'OK' if bad==0 else 'FAIL'}")
    return bad==0

def audit_null_pe():
    tb=r"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0; reg [7:0] op; reg [15:0] id; reg act; wire pg,cg,v;
 null_pe u(.clk(clk),.reset_n(rst_n),.opcode(op),.pe_id(id),.activate(act),.power_gate_en(pg),.clock_gate_en(cg),.valid(v));
 always #5 clk=~clk;
 initial begin @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
  @(negedge clk) begin op=8'hEA; act=1; end @(negedge clk) #1 $display("R 1 %b %b",pg,cg);
  @(negedge clk) act=0; @(negedge clk) #1 $display("R 0 %b %b",pg,cg); $finish; end endmodule"""
    bad=0
    for l in grab(sim(["null_pe.v"],tb,"null"),"R "):
        a,pg,cg=l.split(); bad+= 0 if (pg==a and cg==a) else 1
    print(f"null_pe       : power/clock gate == activate  -> {'OK' if bad==0 else 'FAIL'}")
    return bad==0

def audit_dfs_gate():
    tb=r"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0; reg [7:0] op; reg [15:0] d; reg vis; wire [15:0] sc; wire se,v;
 dfs_gate u(.clk(clk),.reset_n(rst_n),.opcode(op),.depth_counter(d),.visited_flag(vis),.skip_counter(sc),.skip_enable(se),.valid(v));
 always #5 clk=~clk;
 task k(input[15:0]dd,input vv); begin @(negedge clk) begin op=8'hE7;d=dd;vis=vv; end @(negedge clk) #1 $display("R %b %b",((dd>16)&&!vv),se); end endtask
 initial begin @(negedge clk) rst_n=0; @(negedge clk) rst_n=1; k(20,0); k(20,1); k(10,0); k(17,0); $finish; end endmodule"""
    bad=0
    for l in grab(sim(["dfs_gate.v"],tb,"dfs"),"R "):
        exp,se=l.split(); bad+= 0 if se==exp else 1
    print(f"dfs_gate      : skip==(depth>16 && !visited)  -> {'OK' if bad==0 else 'FAIL'}")
    return bad==0

def audit_subth_clk():
    tb=r"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0; reg [7:0] op; reg [2:0] dv; reg eg; reg [7:0] dc; wire [7:0] co,cf; wire ga;
 subth_clk u(.clk_in(clk),.rst_n(rst_n),.opcode(op),.divider(dv),.enable_gate(eg),.duty_cycle(dc),.clk_out(co),.gate_active(ga),.clk_freq(cf));
 always #5 clk=~clk;
 task k(input[2:0]d); begin @(negedge clk) begin op=8'hE5;dv=d;eg=1; end @(negedge clk) #1 $display("R %0d %0d",(1<<d),cf); end endtask
 initial begin @(negedge clk) rst_n=0; @(negedge clk) rst_n=1; k(0);k(1);k(2);k(3); $finish; end endmodule"""
    bad=0
    for l in grab(sim(["subth_clk.v"],tb,"subth"),"R "):
        exp,cf=l.split(); bad+= 0 if exp==cf else 1
    print(f"subth_clk     : clk_freq == 2^divider  -> {'OK' if bad==0 else 'FAIL'}")
    return bad==0

def round_prob(mod, frac, lsb, n=2048):
    if mod=="stoch_round":
        tb=f"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0; reg [7:0] op; reg [15:0] din,seed; wire [15:0] dout; wire v;
 stoch_round u(.clk(clk),.reset_n(rst_n),.opcode(op),.data_in(din),.random_seed(seed),.data_out(dout),.valid(v));
 always #5 clk=~clk; integer i,up;
 initial begin op=8'hE9; seed=16'h1234; up=0; din=16'h40{lsb:02x};
  @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
  for(i=0;i<{n};i=i+1) begin @(negedge clk); if(dout!=din) up=up+1; end $display("U %0d",up); $finish; end endmodule"""
        src="stoch_round.v"
    else:
        tb=f"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,ena=1; reg [15:0] val; reg [7:0] fr; wire [15:0] res; wire v;
 stoch_round_v2 u(.clk(clk),.reset_n(rst_n),.ena(ena),.value(val),.frac(fr),.result(res),.valid(v));
 always #5 clk=~clk; integer i,up;
 initial begin val=16'h4000; fr=8'd{frac}; up=0;
  @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
  for(i=0;i<{n};i=i+1) begin @(negedge clk); if(res!=val) up=up+1; end $display("U %0d",up); $finish; end endmodule"""
        src="stoch_round_v2.v"
    return int(grab(sim([src],tb,mod),"U ")[0]), n

def audit_stoch():
    up1,n=round_prob("stoch_round",0,1); up0,_=round_prob("stoch_round",0,0)
    shipped_wrong=(abs(up1/n-0.5)<0.1) and up0==0
    ok=True
    for frac in (0,64,128,192,255):
        up,n=round_prob("v2",frac,0); ok &= abs(up/n-frac/256.0)<0.05
    print(f"stoch_round   : shipped is prob=0.5*LSB (NOT stochastic): {shipped_wrong}")
    print(f"stoch_round_v2: unbiased P(up)==frac/256  -> {'OK' if ok else 'FAIL'}")
    return shipped_wrong and ok

def audit_opcode_widths():
    """every power unit's opcode port must be >= 8 bits to hold its sacred opcode."""
    want = {"sparse_skip":"E1","subth_clk":"E5","fbb_active_path":"F2",
            "stoch_round":"E9","spec_exit":"EB","null_pe":"EA","dfs_gate":"E7"}
    bad=[]
    for m,oc in want.items():
        t=open(os.path.join(SRC,m+".v")).read()
        w=re.search(r"\[(\d+):0\]\s+opcode", t)
        if not w or int(w.group(1)) < 7: bad.append(m)
    print(f"opcode-width  : all 7 units have >=8-bit opcode ports (no 0x{','.join(want.values())} truncation)"
          f"  -> {'OK' if not bad else 'NARROW: '+','.join(bad)}")
    return not bad

def main():
    print("== power/sparsity wave (39-42) audit -- dead-code library units ==")
    r=[audit_sparse_skip(), audit_spec_exit(), audit_null_pe(), audit_dfs_gate(),
       audit_subth_clk(), audit_stoch(), audit_opcode_widths()]
    ok=all(r)
    print("RESULT:", "all power-wave units conform (stoch_round defect -> v2; opcode widths fixed)"
          if ok else "FAIL")
    return 0 if ok else 1

if __name__=="__main__":
    sys.exit(main())
