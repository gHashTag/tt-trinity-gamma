#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Control / datapath fabric conformance audit.
#
# Audits the instantiated mesh-fabric blocks against their stated behaviour, the
# same "RTL vs the contract it claims" method that found the gf16_mul / bitnet /
# blake3 defects. Covers:
#
#   trinity_router_2x2   -- forward path is one-hot to the addressed tile (dst in
#                           pkt[27:26]) with full broadcast; return path is a fair
#                           round-robin over the 4 tiles.
#   trinity_mesh_2x2     -- end-to-end LOAD_A/LOAD_B/COMPUTE/READ_RES of the
#                           canonical vectors [1,2,3,4].[1,2,3,4] yields 0x47C0
#                           (= 30.0 in GF16) at dbg_tile0_result.
#   multi_tile_receipt   -- characterises the NBA last-wins defect: four DISTINCT
#                           tiles valid in ONE cycle drop all but t3 (the XOR-sum
#                           is wrong); staggered across cycles it is correct. The
#                           multi_tile_receipt_v2 fix accumulates all simultaneous
#                           contributions. (On the shipped dies all four ports are
#                           tied to one source, so the bug is benign there -- see
#                           the v2 header; this test documents the contract gap.)
#
# 2026-06 result: router + mesh CORRECT; multi_tile_receipt has the latent NBA gap,
# multi_tile_receipt_v2 fixes it.
import os, subprocess, tempfile, glob, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC  = os.path.join(ROOT, "src")

def sim(tb_text, files, tag, incdir=True):
    d = tempfile.mkdtemp(); open(d+"/tb.v","w").write(tb_text)
    cmd = ["iverilog","-g2012"] + (["-I",SRC] if incdir else []) + ["-o",d+"/x",*files,d+"/tb.v"]
    c = subprocess.run(cmd, capture_output=True, text=True)
    if c.returncode:
        print(f"{tag}: COMPILE FAIL\n{c.stderr[-600:]}"); sys.exit(2)
    return subprocess.run(["vvp",d+"/x"], capture_output=True, text=True).stdout

# ----------------------------------------------------------- trinity_router_2x2
def audit_router():
    fwd = r"""`timescale 1ns/1ps
`include "trinity_packet.vh"
module tb; reg clk=0,rst_n=1; integer k; reg [31:0] hp; reg hv; wire hir;
 reg hor; wire [31:0] hop; wire hov; wire [127:0] tpf; wire [3:0] tv; reg [3:0] tr;
 reg [127:0] trpf; reg [3:0] trv; wire [3:0] trr;
 trinity_router_2x2 u(.clk(clk),.rst_n(rst_n),.host_in_pkt(hp),.host_in_valid(hv),
  .host_in_ready(hir),.host_out_pkt(hop),.host_out_valid(hov),.host_out_ready(hor),
  .t_pkt_flat(tpf),.t_valid(tv),.t_ready(tr),.t_ret_pkt_flat(trpf),.t_ret_valid(trv),.t_ret_ready(trr));
 always #5 clk=~clk;
 initial begin hv=0;hor=0;tr=4'b1111;trv=0;trpf=0;
  for(k=0;k<4;k=k+1) begin hp={`TRN_OP_COMPUTE,k[1:0],2'd0,4'h0,4'h0,16'hBEEF}; hv=1;
   #1 $display("F %0d %04b %b", k, tv,
     (tpf[31:0]==hp)&&(tpf[63:32]==hp)&&(tpf[95:64]==hp)&&(tpf[127:96]==hp)); end
  $finish; end endmodule"""
    out = sim(fwd, [os.path.join(SRC,"trinity_router_2x2.v")], "router-fwd")
    onehot = {0:"0001",1:"0010",2:"0100",3:"1000"}
    fwd_ok = all(len(p.split())==3 and p.split()[1]==onehot[int(p.split()[0])] and p.split()[2]=="1"
                 for p in [l[2:] for l in out.splitlines() if l.startswith("F ")])

    ret = r"""`timescale 1ns/1ps
`include "trinity_packet.vh"
module tb; reg clk=0,rst_n=0; integer k; reg [31:0] hp=0; reg hv=0; wire hir;
 reg hor; wire [31:0] hop; wire hov; wire [127:0] tpf; wire [3:0] tv; reg [3:0] tr=0;
 reg [127:0] trpf; reg [3:0] trv; wire [3:0] trr;
 trinity_router_2x2 u(.clk(clk),.rst_n(rst_n),.host_in_pkt(hp),.host_in_valid(hv),
  .host_in_ready(hir),.host_out_pkt(hop),.host_out_valid(hov),.host_out_ready(hor),
  .t_pkt_flat(tpf),.t_valid(tv),.t_ready(tr),.t_ret_pkt_flat(trpf),.t_ret_valid(trv),.t_ret_ready(trr));
 always #5 clk=~clk;
 initial begin trpf={32'd3,32'd2,32'd1,32'd0}; trv=4'b1111; hor=1'b1;
  @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
  for(k=0;k<8;k=k+1) begin @(negedge clk); #1 if(hov) $display("R %0d", hop); end
  $finish; end endmodule"""
    out = sim(ret, [os.path.join(SRC,"trinity_router_2x2.v")], "router-ret")
    seq = [int(l[2:]) for l in out.splitlines() if l.startswith("R ")]
    # fair: first 4 served are a permutation of {0,1,2,3} and it then repeats
    rr_ok = len(seq) >= 8 and set(seq[:4]) == {0,1,2,3} and seq[:4] == seq[4:8]
    ok = fwd_ok and rr_ok
    print(f"trinity_router_2x2 : forward one-hot {fwd_ok}; return round-robin fair {rr_ok} "
          f"(order {seq[:4]})  -> {'OK' if ok else 'FAIL'}")
    return ok

# ------------------------------------------------------------- trinity_mesh_2x2
def audit_mesh():
    tb = r"""`timescale 1ns/1ps
`include "trinity_packet.vh"
module tb; reg clk=0,rst_n=0; reg [31:0] hp; reg hv; wire hir;
 wire [31:0] hop; wire hov; reg hor; wire [15:0] dbg;
 trinity_mesh_2x2 dut(.clk(clk),.rst_n(rst_n),.host_in_pkt(hp),.host_in_valid(hv),
  .host_in_ready(hir),.host_out_pkt(hop),.host_out_valid(hov),.host_out_ready(hor),
  .dbg_tile0_result(dbg));
 always #5 clk=~clk;
 task send(input [31:0] p); begin hp=p; hv=1; @(posedge clk); while(!hir) @(posedge clk);
   hv=0; @(posedge clk); end endtask
 reg [15:0] A [0:3]; integer i;
 initial begin hv=0; hor=1; A[0]=16'h3E00;A[1]=16'h4000;A[2]=16'h4100;A[3]=16'h4200;
  @(negedge clk) rst_n=0; repeat(4)@(negedge clk); rst_n=1; repeat(4)@(negedge clk);
  for(i=0;i<4;i=i+1) send(`TRN_MK_PKT(`TRN_OP_LOAD_A,2'd0,2'd0,i[3:0],A[i]));
  for(i=0;i<4;i=i+1) send(`TRN_MK_PKT(`TRN_OP_LOAD_B,2'd0,2'd0,i[3:0],A[i]));
  send(`TRN_MK_PKT(`TRN_OP_COMPUTE,2'd0,2'd0,4'd0,16'h0));
  send(`TRN_MK_PKT(`TRN_OP_READ_RES,2'd0,2'd0,4'd0,16'h0));
  repeat(8)@(negedge clk); $display("M %04h", dbg); $finish; end endmodule"""
    # exclude any testbench files that may live in src/ (euler keeps a tb there);
    # their own initial/$finish blocks would otherwise pre-empt this sim.
    srcs = [f for f in glob.glob(os.path.join(SRC,"*.v"))
            if not os.path.basename(f).startswith("tb_")]
    out = sim(tb, srcs, "mesh")
    got = next((l[2:].strip() for l in out.splitlines() if l.startswith("M ")), None)
    ok = (got is not None) and int(got,16) == 0x47C0
    print(f"trinity_mesh_2x2   : dot4([1,2,3,4].[1,2,3,4]) = 0x{got} (expect 0x47c0 = 30.0)"
          f"  -> {'OK' if ok else 'FAIL'}")
    return ok

# -------------------------------------------------------- multi_tile_receipt(_v2)
def audit_mtr():
    def drive(mod, src, cycles):
        body=""
        for cyc in cycles:
            sets=[]
            for t in range(4):
                if t in cyc:
                    c,j=cyc[t]; sets.append(f"t{t}_valid=1;t{t}_checksum=8'h{c:02x};t{t}_job_id=8'h{j:02x};")
                else: sets.append(f"t{t}_valid=0;")
            body+="   @(negedge clk) begin "+" ".join(sets)+" end\n"
        tb=f"""`timescale 1ns/1ps
module tb; reg clk=0,rst_n=0;
 reg t0_valid=0,t1_valid=0,t2_valid=0,t3_valid=0;
 reg [7:0] t0_checksum=0,t1_checksum=0,t2_checksum=0,t3_checksum=0;
 reg [7:0] t0_job_id=0,t1_job_id=0,t2_job_id=0,t3_job_id=0;
 wire [7:0] ac,aj; wire [3:0] mask; wire alla,ok;
 {mod} u(.clk(clk),.rst_n(rst_n),
  .t0_valid(t0_valid),.t0_checksum(t0_checksum),.t0_job_id(t0_job_id),
  .t1_valid(t1_valid),.t1_checksum(t1_checksum),.t1_job_id(t1_job_id),
  .t2_valid(t2_valid),.t2_checksum(t2_checksum),.t2_job_id(t2_job_id),
  .t3_valid(t3_valid),.t3_checksum(t3_checksum),.t3_job_id(t3_job_id),
  .agg_checksum(ac),.agg_job_id(aj),.attested_mask(mask),.all_attested(alla),.multi_rcpt_ok(ok));
 always #5 clk=~clk;
 initial begin @(negedge clk) rst_n=0; @(negedge clk) rst_n=1;
{body}   @(negedge clk) begin t0_valid=0;t1_valid=0;t2_valid=0;t3_valid=0; end
  #1 $display("X %02h %b", ac, mask); $finish; end endmodule"""
        out=sim(tb,[os.path.join(SRC,src)],mod,incdir=False)
        l=next(x[2:] for x in out.splitlines() if x.startswith("X "))
        return l.split()[0], l.split()[1]
    cs={0:0x11,1:0x22,2:0x44,3:0x88}
    one=[{t:(cs[t],0) for t in range(4)}]
    sep=[{t:(cs[t],0)} for t in range(4)]
    xall=cs[0]^cs[1]^cs[2]^cs[3]
    # shipped: 4-in-one-cycle keeps only t3 (bug); staggered = correct
    s_one,_ = drive("multi_tile_receipt","multi_tile_receipt.v",one)
    s_sep,_ = drive("multi_tile_receipt","multi_tile_receipt.v",sep)
    bug = (int(s_one,16)==cs[3]) and (int(s_sep,16)==xall)
    # v2: both correct
    v_one,_ = drive("multi_tile_receipt_v2","multi_tile_receipt_v2.v",one)
    v_sep,_ = drive("multi_tile_receipt_v2","multi_tile_receipt_v2.v",sep)
    fixed = (int(v_one,16)==xall) and (int(v_sep,16)==xall)
    ok = bug and fixed
    print(f"multi_tile_receipt : shipped drops simultaneous tiles (1-cyc=0x{s_one} vs xor-all "
          f"0x{xall:02x}; staggered=0x{s_sep}); v2 correct both ways (0x{v_one}/0x{v_sep})"
          f"  -> {'CONTRACT GAP CONFIRMED + FIXED' if ok else 'UNEXPECTED'}")
    return ok

def main():
    print("== control / datapath fabric conformance audit ==")
    r = [audit_router(), audit_mesh(), audit_mtr()]
    allok = all(r)
    print("RESULT:", "router+mesh CORRECT; multi_tile_receipt latent-gap characterized + v2 fix verified"
          if allok else "UNEXPECTED")
    return 0 if allok else 1

if __name__ == "__main__":
    sys.exit(main())
