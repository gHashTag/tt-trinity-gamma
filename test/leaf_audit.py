#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Instantiated leaf-block conformance audit (host bus / PLL / status / ALU).
#
# The arithmetic, crypto/identity, and fabric layers are audited (loops 119-148);
# this covers the remaining instantiated leaf blocks against their stated contracts:
#
#   phi_pll_div    -- fractional divider must emit 5 ticks / 8 clocks (0.625 ~ 1/phi)
#   wishbone_full  -- WB hub: scratch regs 4..15 are R/W, regs 0..3 are RO status
#                     mirrors, writes to RO regs are ignored
#   wb_status_reg  -- packs the documented status bits; `alive` toggles each
#                     post_done rising edge
#   alu9_decoder   -- ternary ALU vs a {-1,0,+1} reference. FINDING: op7 TRI_BIND
#                     uses bitwise `^` on signed lifts, not VSA bind (= ternary
#                     multiply); 6/9 pairs wrong (incl. bind(x,0) != 0). Benign on
#                     silicon (ALU fed by random hwrng bits -> ring27 liveness).
#                     alu9_decoder_v2 fixes BIND -> 81/81 vs reference.
#
# 2026-06 result: phi_pll_div / wishbone_full / wb_status_reg CORRECT;
# alu9_decoder BIND contract gap confirmed, alu9_decoder_v2 verified.
import os, subprocess, tempfile, sys
HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")

def sim(src_files, tb, tag):
    d=tempfile.mkdtemp(); open(d+"/tb.v","w").write(tb)
    files=[os.path.join(SRC,f) for f in src_files]+[d+"/tb.v"]
    c=subprocess.run(["iverilog","-g2012","-o",d+"/x",*files],capture_output=True,text=True)
    if c.returncode: print(f"{tag}: COMPILE FAIL\n{c.stderr[:300]}"); sys.exit(2)
    return subprocess.run(["vvp",d+"/x"],capture_output=True,text=True).stdout

def lines(out,pfx): return [l[len(pfx):].strip() for l in out.splitlines() if l.startswith(pfx)]

def audit_phi():
    tb=r"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0; wire tick; wire [2:0] st; wire ok; integer n,c;
 phi_pll_div u(.clk(clk),.rst_n(rst_n),.phi_tick(tick),.state(st),.phi_div_ok(ok));
 always #5 clk=~clk;
 initial begin n=0; @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
  for(c=0;c<8;c=c+1) begin @(negedge clk); if(tick) n=n+1; end
  $display("T %0d", n); $finish; end endmodule"""
    n=int(lines(sim(["phi_pll_div.v"],tb,"phi"),"T ")[0])
    ok=(n==5)
    print(f"phi_pll_div   : {n} ticks / 8 clocks (expect 5 = 0.625 ~ 1/phi)  -> {'OK' if ok else 'FAIL'}")
    return ok

def audit_wb():
    tb=r"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0,cyc=0,stb=0,we=0; reg [3:0] adr; reg [7:0] dw;
 wire [7:0] dr; wire ack,ok; reg [7:0] status=8'hA5,mm=8'h11,chk=8'h22,bpb=8'h33;
 wishbone_full u(.clk(clk),.rst_n(rst_n),.wb_cyc(cyc),.wb_stb(stb),.wb_we(we),
  .wb_adr(adr),.wb_dat_w(dw),.wb_dat_r(dr),.wb_ack(ack),
  .status_byte(status),.matmul_lo(mm),.rcpt_chk(chk),.bpb_lo(bpb),.wb_ok(ok));
 always #5 clk=~clk;
 task wr(input [3:0]ad,input[7:0]d); begin @(negedge clk) begin cyc=1;stb=1;we=1;adr=ad;dw=d; end
   @(negedge clk) while(!ack)@(negedge clk); @(negedge clk) begin cyc=0;stb=0;we=0; end end endtask
 task rd(input [3:0]ad); begin @(negedge clk) begin cyc=1;stb=1;we=0;adr=ad; end
   @(negedge clk) while(!ack)@(negedge clk); #1 $display("R %0d %02h", ad, dr);
   @(negedge clk) begin cyc=0;stb=0; end end endtask
 initial begin @(negedge clk) rst_n=0; repeat(2)@(negedge clk); rst_n=1; repeat(2)@(negedge clk);
  wr(4'd5,8'hDE); rd(4'd5); rd(4'd0); rd(4'd2); wr(4'd2,8'hFF); rd(4'd2); $finish; end endmodule"""
    r=dict(l.split() for l in lines(sim(["wishbone_full.v"],tb,"wb"),"R "))
    # 4 reads: reg5 first read gives DE; reg0=A5; reg2=22; reg2 after RO write=22
    ok=(r.get("5")=="de") and (r.get("0")=="a5") and (r.get("2")=="22")
    print(f"wishbone_full : reg5(RW)={r.get('5')} reg0(status)={r.get('0')} "
          f"reg2(rcpt,RO-write-ignored)={r.get('2')}  -> {'OK' if ok else 'FAIL'}")
    return ok

def audit_status():
    tb=r"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0; reg phi=1,luc=1,mm=1,pd=0,rcv=1,rng=1; wire [7:0] s;
 wb_status_reg u(.clk(clk),.rst_n(rst_n),.phi_ok(phi),.lucas_ok(luc),.matmul_ok(mm),
  .post_done(pd),.rcpt_valid(rcv),.hwrng_nonzero(rng),.status_byte(s));
 always #5 clk=~clk;
 initial begin @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
  @(negedge clk) #1 $display("P %08b", s);
  @(negedge clk) pd=1; @(negedge clk) #1 $display("A %b", s[7]);
  @(negedge clk) pd=0; @(negedge clk) pd=1; @(negedge clk) #1 $display("B %b", s[7]);
  $finish; end endmodule"""
    out=sim(["wb_status_reg.v"],tb,"status")
    packed=lines(out,"P ")[0]              # {alive,0,hwrng,rcpt,post,matmul,lucas,phi}
    a1=lines(out,"A ")[0]; a2=lines(out,"B ")[0]
    # phi=lucas=mm=rcpt=hwrng=1, post=0, alive=0 -> 0 0 1 1 0 1 1 1 = 00110111
    ok=(packed=="00110111") and a1=="1" and a2=="0"
    print(f"wb_status_reg : packed={packed} (expect 00110111); alive toggles {a1}->{a2}"
          f"  -> {'OK' if ok else 'FAIL'}")
    return ok

def audit_alu():
    def dec(t): return {0:1,1:-1,2:0,3:0}[t]
    def enc(v): return 0 if v>0 else (1 if v<0 else 2)
    def ref(op,sa,sb):
        sgn=lambda s:1 if s>0 else(-1 if s<0 else 0)
        return [0, sgn(sa+sb), sgn(sa-sb),
                (0 if sa==0 or sb==0 else (1 if sa==sb else -1)),
                min(sa,sb), max(sa,sb), -sa,
                (0 if sa==0 or sb==0 else (1 if sa==sb else -1)),  # BIND = ternary multiply
                sgn(sa+sb)][op]
    def run(mod, src):
        tb=f"""`timescale 1ns/1ps
module tb; reg [3:0] op; reg [1:0] a,b; wire [1:0] r; wire v,ok; integer o,x,y;
 {mod} u(.opcode(op),.a(a),.b(b),.result(r),.valid(v),.decoder_ok(ok));
 initial begin for(o=0;o<9;o=o+1) for(x=0;x<3;x=x+1) for(y=0;y<3;y=y+1) begin
   op=o[3:0]; a=x[1:0]; b=y[1:0]; #1 $display("Z %0d %0d %0d %0d", o,x,y,r); end $finish; end endmodule"""
        miss=0
        for l in lines(sim([src],tb,mod),"Z "):
            o,x,y,r=map(int,l.split())
            if r != enc(ref(o,dec(x),dec(y))): miss+=1
        return miss
    shipped=run("alu9_decoder","alu9_decoder.v")
    fixed=run("alu9_decoder_v2","alu9_decoder_v2.v")
    ok=(shipped==6) and (fixed==0)
    print(f"alu9_decoder  : shipped BIND gap = {shipped}/81 mismatches (all op7); "
          f"v2 = {fixed}/81  -> {'BIND GAP CONFIRMED + FIXED' if ok else 'UNEXPECTED'}")
    return ok

def main():
    print("== instantiated leaf-block conformance audit ==")
    r=[audit_phi(), audit_wb(), audit_status(), audit_alu()]
    allok=all(r)
    print("RESULT:", "phi/wb/status CORRECT; alu9 BIND gap characterized + v2 fix verified"
          if allok else "UNEXPECTED")
    return 0 if allok else 1

if __name__=="__main__":
    sys.exit(main())
