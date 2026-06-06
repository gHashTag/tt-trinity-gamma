#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Replay the committed trained gf16 model (test/gf16_model/) through the ACTUAL RTL.
#
# Loads the gf16 weights + eval set produced by gen_gf16_model.py and runs the
# 2-layer forward pass (15 PCA -> 15 ReLU -> 10) through dot16 (shipped gf16_mul +
# gf16_add) vs dot16_v2 (corrected), with gf16 ReLU between layers. Reports shipped /
# corrected / exact accuracy and the Defect-1 argmax-flip rate. NO sklearn / no
# training -- pure gf16 inference from the saved artifacts (reproducible lever for
# the respin's Defect-1 task number). Needs only iverilog + Python stdlib.
import os, subprocess, sys, tempfile
from fractions import Fraction
HERE=os.path.dirname(os.path.abspath(__file__)); SRC=os.path.join(HERE,"..","src")
MODEL=os.path.join(HERE,"gf16_model")
BIAS,NIN,HID,CLS=31,16,15,10; ONE=0x3E00   # gf16 1.0

def decode(c):
    s=(c>>15)&1; e=(c>>9)&0x3F; m=c&0x1FF
    if e==0 and m==0: return Fraction(0)
    if e==0x3F: return None
    return (-1 if s else 1)*Fraction(512+m)*Fraction(2)**(e-BIAS-9)
def encode(x):
    if x==0: return 0
    s=1 if x<0 else 0; ax=abs(float(x)); e=BIAS
    while ax>=2.0**(e-BIAS+1) and e<62: e+=1
    while ax<2.0**(e-BIAS) and e>1: e-=1
    m=int(round((ax/2.0**(e-BIAS)-1.0)*512))
    if m>=512: m=0; e+=1
    if e>=63: return (s<<15)|(63<<9)
    if e<1: return 0
    return (s<<15)|(e<<9)|m
def relu(c): return 0 if (c>>15)&1 else c
def pack(v):
    w=0
    for k,x in enumerate(v): w|=(x&0xFFFF)<<(16*k)
    return w
def rows_mem(fn): return [[int(t,16) for t in l.split()] for l in open(fn) if l.strip()]

TB="""`timescale 1ns/1ps
module tb; reg [255:0] av[0:{nm1}]; reg [255:0] wv[0:{nm1}]; reg [255:0] a,w;
 wire [15:0] r_o,r_n; dot16 uo(.a(a),.w(w),.result(r_o)); dot16_v2 un(.a(a),.w(w),.result(r_n));
 integer i; initial begin $readmemh("{af}",av); $readmemh("{wf}",wv);
  for(i=0;i<{n};i=i+1) begin a=av[i]; w=wv[i]; #1; $display("R %04h %04h",r_o,r_n); end $finish; end endmodule
"""
def drive(pairs):
    n=len(pairs)
    with tempfile.TemporaryDirectory() as t:
        af,wf=os.path.join(t,"a.hex"),os.path.join(t,"w.hex")
        open(af,"w").write("\n".join("%064x"%a for a,_ in pairs))
        open(wf,"w").write("\n".join("%064x"%w for _,w in pairs))
        tbp,outp=os.path.join(t,"tb.v"),os.path.join(t,"sim")
        open(tbp,"w").write(TB.format(nm1=n-1,n=n,af=af,wf=wf))
        c=subprocess.run(["iverilog","-g2012","-o",outp,
            os.path.join(SRC,"dot16_study.v"),os.path.join(SRC,"gf16_dot4.v"),
            os.path.join(SRC,"gf16_dot4_v2.v"),os.path.join(SRC,"gf16_mul.v"),
            os.path.join(SRC,"gf16_add.v"),os.path.join(SRC,"gf16_v2_mul.v"),
            os.path.join(SRC,"gf16_v2_add.v"),tbp],capture_output=True,text=True)
        if c.returncode: print("iverilog FAILED:\n"+c.stderr); sys.exit(2)
        return [(int(l.split()[1],16),int(l.split()[2],16))
                for l in subprocess.run(["vvp",outp],capture_output=True,text=True).stdout.splitlines() if l.startswith("R ")]
def exact_dot(aq,wq): return sum(decode(aq[k])*decode(wq[k]) for k in range(NIN))

def main():
    for f in ("W1.mem","W2.mem","eval_X.mem","eval_y.txt"):
        if not os.path.exists(os.path.join(MODEL,f)):
            print("missing artifact:",f,"-- run test/gen_gf16_model.py first"); return 1
    W1=rows_mem(os.path.join(MODEL,"W1.mem")); W2=rows_mem(os.path.join(MODEL,"W2.mem"))
    X=rows_mem(os.path.join(MODEL,"eval_X.mem"))
    y=[int(l) for l in open(os.path.join(MODEL,"eval_y.txt")) if l.strip()]
    nT=len(X)
    print(f"Trained gf16 model replay (artifacts in test/gf16_model/): "
          f"{nT} eval samples, 2-layer 15->15->10\n")
    # layer 1
    l1=[(pack(X[i]),pack(W1[j])) for i in range(nT) for j in range(HID)]
    o1=drive(l1)
    sh_h=[[0]*NIN for _ in range(nT)]; v2_h=[[0]*NIN for _ in range(nT)]; ex_h=[[0]*NIN for _ in range(nT)]
    for i in range(nT):
        for j in range(HID):
            ro,rn=o1[i*HID+j]; sh_h[i][j]=relu(ro); v2_h[i][j]=relu(rn)
            ev=exact_dot(X[i],W1[j]); ex_h[i][j]=encode(float(ev if ev>0 else 0))
        sh_h[i][HID]=ONE; v2_h[i][HID]=ONE; ex_h[i][HID]=ONE
    # layer 2 (shipped reads r_o on shipped hidden; corrected reads r_n on v2 hidden)
    o2s=drive([(pack(sh_h[i]),pack(W2[o])) for i in range(nT) for o in range(CLS)])
    o2v=drive([(pack(v2_h[i]),pack(W2[o])) for i in range(nT) for o in range(CLS)])
    acc_sh=acc_v2=acc_ex=fsv=0; ldiff=0
    for i in range(nT):
        sh=[decode(o2s[i*CLS+o][0]) for o in range(CLS)]
        v2=[decode(o2v[i*CLS+o][1]) for o in range(CLS)]
        ex=[exact_dot(ex_h[i],W2[o]) for o in range(CLS)]
        if any(v is None for v in sh+v2): continue
        for o in range(CLS): ldiff+=(o2s[i*CLS+o][0]!=o2v[i*CLS+o][1])
        a_sh=max(range(CLS),key=lambda j:sh[j]); a_v2=max(range(CLS),key=lambda j:v2[j])
        a_ex=max(range(CLS),key=lambda j:ex[j])
        acc_sh+=(a_sh==y[i]); acc_v2+=(a_v2==y[i]); acc_ex+=(a_ex==y[i]); fsv+=(a_sh!=a_v2)
    print(f"  accuracy vs labels:  shipped {100*acc_sh/nT:.2f}%   corrected(v2) {100*acc_v2/nT:.2f}%   exact {100*acc_ex/nT:.2f}%")
    print(f"  defect active: {ldiff}/{nT*CLS} output logits differ shipped vs v2")
    print(f"  Defect-1 argmax-flip shipped vs v2: {fsv}/{nT} = {100*fsv/nT:.3f}%")
    print("RESULT: trained gf16 model replayed through RTL from committed artifacts")
    return 0

if __name__=="__main__":
    sys.exit(main())
