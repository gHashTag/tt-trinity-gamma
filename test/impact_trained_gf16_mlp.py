#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Defect-1 (gf16_mul) task impact on a DEEPER (2-layer) trained model.
#
# The single-layer study (impact_trained_gf16.py) showed Defect-1 flips ~0.13% of
# predictions on a trained linear classifier. Open question: does the error COMPOUND
# with depth? A 2-layer MLP runs two gf16 MAC layers, so per-layer rounding/halving
# error can accumulate through the hidden activations. This trains an MLP
# (15 PCA -> 15 ReLU hidden -> 10) on sklearn digits, quantizes weights + activations
# to gf16, and runs BOTH layers through the ACTUAL RTL (dot16 shipped gf16_mul+add vs
# dot16_v2), with gf16 ReLU between layers, keeping the shipped and corrected forward
# passes fully separate. Reports the argmax-flip rate and accuracy delta -- the
# depth-robustness check behind the brief's "task-quiet" conclusion.
import os, subprocess, sys, tempfile
from fractions import Fraction
try:
    import numpy as np
    from sklearn.datasets import load_digits
    from sklearn.decomposition import PCA
    from sklearn.preprocessing import StandardScaler
    from sklearn.neural_network import MLPClassifier
    from sklearn.model_selection import train_test_split
except Exception as e:
    print("SKIP: needs numpy + scikit-learn (", e, ")"); sys.exit(0)

HERE=os.path.dirname(os.path.abspath(__file__)); SRC=os.path.join(HERE,"..","src")
BIAS,NIN,HID,CLS=31,16,15,10

def decode(code):
    s=(code>>15)&1; e=(code>>9)&0x3F; m=code&0x1FF
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
def relu_code(c): return 0 if (c>>15)&1 else c
def pack(vec):
    w=0
    for k,v in enumerate(vec): w|=(v&0xFFFF)<<(16*k)
    return w
ONE=encode(1.0)

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

def exact_dot(aq,wq):  # rational dot of quantized operand codes
    return sum(decode(aq[k])*decode(wq[k]) for k in range(NIN))

def run_split(seed):
    d=load_digits()
    Xtr,Xte,ytr,yte=train_test_split(d.data,d.target,test_size=0.25,random_state=seed,stratify=d.target)
    sc=StandardScaler().fit(Xtr); pca=PCA(n_components=15,random_state=seed).fit(sc.transform(Xtr))
    Ztr=pca.transform(sc.transform(Xtr)); Zte=pca.transform(sc.transform(Xte))
    clf=MLPClassifier(hidden_layer_sizes=(HID,),activation='relu',max_iter=800,
                      random_state=seed,alpha=1e-3).fit(Ztr,ytr)
    float_acc=(clf.predict(Zte)==yte).mean()
    W1=clf.coefs_[0]; b1=clf.intercepts_[0]   # (15,15),(15,)
    W2=clf.coefs_[1]; b2=clf.intercepts_[1]   # (15,10),(10,)
    W1q=[[encode(W1[k,j]) for k in range(HID)]+[encode(b1[j])] for j in range(HID)]   # 15 rows x16
    W2q=[[encode(W2[k,o]) for k in range(HID)]+[encode(b2[o])] for o in range(CLS)]   # 10 rows x16
    nT=len(Zte)
    # input vectors (15 PCA + bias), quantized
    Xq=[[encode(Zte[i,k]) for k in range(HID)]+[ONE] for i in range(nT)]
    # ---- Layer 1: dot16(x', W1[j]) for all samples,hidden ----
    l1=[(pack(Xq[i]),pack(W1q[j])) for i in range(nT) for j in range(HID)]
    o1=drive(l1)
    sh_h=[[0]*NIN for _ in range(nT)]; v2_h=[[0]*NIN for _ in range(nT)]; ex_h=[[0]*NIN for _ in range(nT)]
    l1diff=0
    for i in range(nT):
        for j in range(HID):
            ro,rn=o1[i*HID+j]; l1diff+=(ro!=rn)
            sh_h[i][j]=relu_code(ro); v2_h[i][j]=relu_code(rn)
            exv=exact_dot(Xq[i],W1q[j]); exr=exv if exv>0 else Fraction(0)
            ex_h[i][j]=encode(float(exr))
        sh_h[i][HID]=ONE; v2_h[i][HID]=ONE; ex_h[i][HID]=ONE
    # ---- Layer 2: shipped uses sh_h (read r_o); v2 uses v2_h (read r_n) ----
    l2s=[(pack(sh_h[i]),pack(W2q[o])) for i in range(nT) for o in range(CLS)]
    l2v=[(pack(v2_h[i]),pack(W2q[o])) for i in range(nT) for o in range(CLS)]
    o2s=drive(l2s); o2v=drive(l2v)
    acc_sh=acc_v2=acc_ex=fsv=fse=0; l2diff=0; nl2=0
    for i in range(nT):
        sh=[decode(o2s[i*CLS+o][0]) for o in range(CLS)]
        v2=[decode(o2v[i*CLS+o][1]) for o in range(CLS)]
        ex=[exact_dot(ex_h[i],W2q[o]) for o in range(CLS)]
        if any(v is None for v in sh+v2): continue
        for o in range(CLS): nl2+=1; l2diff+=(o2s[i*CLS+o][0]!=o2v[i*CLS+o][1])
        am_sh=max(range(CLS),key=lambda j:sh[j]); am_v2=max(range(CLS),key=lambda j:v2[j])
        am_ex=max(range(CLS),key=lambda j:ex[j])
        acc_sh+=(am_sh==yte[i]); acc_v2+=(am_v2==yte[i]); acc_ex+=(am_ex==yte[i])
        fsv+=(am_sh!=am_v2); fse+=(am_sh!=am_ex)
    return dict(nT=nT,float_acc=float_acc,acc_sh=acc_sh,acc_v2=acc_v2,acc_ex=acc_ex,
                fsv=fsv,fse=fse,l1diff=l1diff,l2diff=l2diff,nl2=nl2)

def main():
    print("DEEPER-MODEL Defect-1 task impact (sklearn digits, 2-layer MLP 15->15 ReLU->10)")
    print("both gf16 layers through the ACTUAL RTL, gf16 ReLU between; 3 splits:\n")
    tot=dict(nT=0,acc_sh=0,acc_v2=0,acc_ex=0,fsv=0,fse=0,l1diff=0,l2diff=0,nl2=0)
    for seed in (7,13,23):
        r=run_split(seed)
        for k in tot: tot[k]+=r[k]
        print(f"  seed {seed:2d}: test={r['nT']} floatAcc={100*r['float_acc']:.1f}% | "
              f"acc sh/v2/exact={100*r['acc_sh']/r['nT']:.2f}/{100*r['acc_v2']/r['nT']:.2f}/"
              f"{100*r['acc_ex']/r['nT']:.2f}% | flip sh-v2={r['fsv']} | "
              f"L1 diff={r['l1diff']} L2 diff={r['l2diff']}/{r['nl2']}")
    nT=tot['nT']
    print(f"\nAGGREGATE over {nT} test samples (3 splits, 2-layer):")
    print(f"  accuracy vs true labels:  shipped {100*tot['acc_sh']/nT:.2f}%   "
          f"v2 {100*tot['acc_v2']/nT:.2f}%   exact {100*tot['acc_ex']/nT:.2f}%")
    print(f"  DEFECT ACTIVE both layers: L1 {tot['l1diff']} hidden + L2 "
          f"{tot['l2diff']}/{tot['nl2']} output logits differ shipped vs v2")
    print(f"  argmax-flip shipped vs v2 (2-layer Defect-1 number): {tot['fsv']}/{nT} = {100*tot['fsv']/nT:.3f}%")
    print(f"  argmax-flip shipped vs exact                       : {tot['fse']}/{nT} = {100*tot['fse']/nT:.3f}%")
    print(f"  (1-layer was 0.13%; synthetic proxy 0.24%) -> depth-robustness check")
    print("RESULT: 2-layer trained-model Defect-1 number measured (RTL-driven)")
    return 0

if __name__=="__main__":
    sys.exit(main())
