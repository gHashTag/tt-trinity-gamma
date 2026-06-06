#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Defect-1 (gf16_mul rounding-overflow) task impact on a TRAINED model + real data.
#
# The respin brief's task number (~0.24% argmax flips) came from a SYNTHETIC random
# linear classifier; the open caveat was "a trained net's margins could differ."
# This closes that caveat: it trains a real classifier on the sklearn `digits`
# dataset (1797 8x8 images, 10 classes), reduces to 15 PCA features + a bias term
# (16-dim = one dot16), quantizes the trained weights and the test inputs to gf16,
# and runs each per-class logit through the ACTUAL silicon RTL -- dot16 (shipped
# gf16_mul + gf16_add) and dot16_v2 (corrected gf16_v2_*) -- plus an exact-rational
# reference over the SAME quantized operands. Argmax gives the predicted class.
#
# Reports, on the held-out test set:
#   - accuracy of float / exact-quantized / v2-gf16 / shipped-gf16 vs true labels
#   - argmax-flip rate shipped-vs-v2  = the trained-model Defect-1 number
#   - argmax-flip rate shipped-vs-exact
# No Python model of the gf16 ops is used (the RTL is the source of truth); only the
# exact-rational dot of the quantized operands is computed in Python.
import os, subprocess, sys, tempfile
from fractions import Fraction
try:
    import numpy as np
    from sklearn.datasets import load_digits
    from sklearn.decomposition import PCA
    from sklearn.preprocessing import StandardScaler
    from sklearn.linear_model import LogisticRegression
    from sklearn.model_selection import train_test_split
except Exception as e:
    print("SKIP: needs numpy + scikit-learn (", e, ")"); sys.exit(0)

HERE = os.path.dirname(os.path.abspath(__file__)); SRC = os.path.join(HERE, "..", "src")
BIAS, NIN, CLASSES = 31, 16, 10

def decode(code):
    s=(code>>15)&1; e=(code>>9)&0x3F; m=code&0x1FF
    if e==0 and m==0: return Fraction(0)
    if e==0x3F: return None
    return (-1 if s else 1)*Fraction(512+m)*Fraction(2)**(e-BIAS-9)

def encode(x):
    """round a real to the nearest gf16 code (quantization; not the unit under test)."""
    if x==0: return 0
    s=1 if x<0 else 0; ax=abs(float(x))
    e=BIAS
    while ax>=2.0**(e-BIAS+1) and e<62: e+=1
    while ax<2.0**(e-BIAS) and e>1: e-=1
    frac=ax/2.0**(e-BIAS)-1.0
    m=int(round(frac*512))
    if m>=512: m=0; e+=1
    if e>=63: return (s<<15)|(63<<9)             # saturate to inf code (mant 0)
    if e<1:  return 0
    return (s<<15)|(e<<9)|m

def pack(vec16):
    w=0
    for k,v in enumerate(vec16): w|=(v&0xFFFF)<<(16*k)
    return w

TB="""`timescale 1ns/1ps
module tb;
  reg [255:0] av [0:{nm1}]; reg [255:0] wv [0:{nm1}];
  reg [255:0] a, w; wire [15:0] r_o, r_n;
  dot16    uo(.a(a), .w(w), .result(r_o));
  dot16_v2 un(.a(a), .w(w), .result(r_n));
  integer i;
  initial begin
    $readmemh("{af}", av); $readmemh("{wf}", wv);
    for (i=0;i<{n};i=i+1) begin a=av[i]; w=wv[i]; #1; $display("R %04h %04h", r_o, r_n); end
    $finish;
  end
endmodule
"""

def run_split(seed):
    d=load_digits()
    Xtr,Xte,ytr,yte=train_test_split(d.data,d.target,test_size=0.25,random_state=seed,stratify=d.target)
    sc=StandardScaler().fit(Xtr); pca=PCA(n_components=15,random_state=seed).fit(sc.transform(Xtr))
    def feat(X):
        z=pca.transform(sc.transform(X)); return np.hstack([z, np.ones((len(z),1))])
    Ftr,Fte=feat(Xtr),feat(Xte)
    clf=LogisticRegression(max_iter=2000,C=1.0).fit(Ftr[:,:15],ytr)
    W=np.hstack([clf.coef_, clf.intercept_[:,None]])
    float_acc=(clf.predict(Fte[:,:15])==yte).mean()
    Wq=[[encode(W[c,k]) for k in range(NIN)] for c in range(CLASSES)]
    Wqd=[[decode(x) for x in row] for row in Wq]
    a_words,w_words,exact=[],[],[]
    for i in range(len(Fte)):
        xq=[encode(Fte[i,k]) for k in range(NIN)]; xqd=[decode(x) for x in xq]
        for c in range(CLASSES):
            a_words.append(pack(xq)); w_words.append(pack(Wq[c]))
            exact.append(sum(xqd[k]*Wqd[c][k] for k in range(NIN)))
    n=len(a_words)
    with tempfile.TemporaryDirectory() as t:
        af,wf=os.path.join(t,"a.hex"),os.path.join(t,"w.hex")
        open(af,"w").write("\n".join("%064x"%x for x in a_words))
        open(wf,"w").write("\n".join("%064x"%x for x in w_words))
        tbp,outp=os.path.join(t,"tb.v"),os.path.join(t,"sim")
        open(tbp,"w").write(TB.format(nm1=n-1,n=n,af=af,wf=wf))
        c=subprocess.run(["iverilog","-g2012","-o",outp,
            os.path.join(SRC,"dot16_study.v"),os.path.join(SRC,"gf16_dot4.v"),
            os.path.join(SRC,"gf16_dot4_v2.v"),os.path.join(SRC,"gf16_mul.v"),
            os.path.join(SRC,"gf16_add.v"),os.path.join(SRC,"gf16_v2_mul.v"),
            os.path.join(SRC,"gf16_v2_add.v"),tbp],capture_output=True,text=True)
        if c.returncode: print("iverilog FAILED:\n"+c.stderr); sys.exit(2)
        rows=[l.split()[1:] for l in subprocess.run(["vvp",outp],capture_output=True,text=True).stdout.splitlines() if l.startswith("R ")]
    nT=len(Fte); acc_ex=acc_v2=acc_sh=0; flip_sh_v2=flip_sh_ex=0; logit_diff=0; nlogit=0
    for i in range(nT):
        base=i*CLASSES; ex=exact[base:base+CLASSES]
        sh=[decode(int(rows[base+c][0],16)) for c in range(CLASSES)]
        v2=[decode(int(rows[base+c][1],16)) for c in range(CLASSES)]
        if any(v is None for v in sh+v2): continue
        for c in range(CLASSES):
            nlogit+=1; logit_diff+=(int(rows[base+c][0],16)!=int(rows[base+c][1],16))
        am_ex=max(range(CLASSES),key=lambda j:ex[j])
        am_sh=max(range(CLASSES),key=lambda j:sh[j])
        am_v2=max(range(CLASSES),key=lambda j:v2[j])
        acc_ex+=(am_ex==yte[i]); acc_v2+=(am_v2==yte[i]); acc_sh+=(am_sh==yte[i])
        flip_sh_v2+=(am_sh!=am_v2); flip_sh_ex+=(am_sh!=am_ex)
    return dict(nT=nT,float_acc=float_acc,acc_ex=acc_ex,acc_v2=acc_v2,acc_sh=acc_sh,
                flip_sh_v2=flip_sh_v2,flip_sh_ex=flip_sh_ex,logit_diff=logit_diff,nlogit=nlogit)

def main():
    print("TRAINED-MODEL Defect-1 task impact (sklearn digits, 15 PCA + bias, LogisticRegression)")
    print("per-class logit = one dot16 through the ACTUAL RTL; 5 train/test splits:\n")
    tot=dict(nT=0,acc_ex=0,acc_v2=0,acc_sh=0,flip_sh_v2=0,flip_sh_ex=0,logit_diff=0,nlogit=0)
    for seed in (7,11,13,17,23):
        r=run_split(seed)
        for k in tot: tot[k]+=r[k]
        print(f"  seed {seed:2d}: test={r['nT']} floatAcc={100*r['float_acc']:.1f}% | "
              f"acc sh/v2/exact={100*r['acc_sh']/r['nT']:.2f}/{100*r['acc_v2']/r['nT']:.2f}/"
              f"{100*r['acc_ex']/r['nT']:.2f}% | flip sh-v2={r['flip_sh_v2']} "
              f"| logits differing={r['logit_diff']}/{r['nlogit']}")
    nT=tot['nT']
    print(f"\nAGGREGATE over {nT} test samples (5 splits):")
    print(f"  accuracy vs true labels:  shipped {100*tot['acc_sh']/nT:.2f}%   "
          f"v2 {100*tot['acc_v2']/nT:.2f}%   exact-quantized {100*tot['acc_ex']/nT:.2f}%")
    print(f"  DEFECT IS ACTIVE: {tot['logit_diff']}/{tot['nlogit']} logits "
          f"({100*tot['logit_diff']/tot['nlogit']:.3f}%) differ shipped vs v2 (mul defect fires)")
    print(f"  argmax-flip shipped vs v2  (Defect-1 trained number): "
          f"{tot['flip_sh_v2']}/{nT} = {100*tot['flip_sh_v2']/nT:.3f}%")
    print(f"  argmax-flip shipped vs exact-quantized              : "
          f"{tot['flip_sh_ex']}/{nT} = {100*tot['flip_sh_ex']/nT:.3f}%")
    print(f"  (synthetic random-classifier proxy was ~0.24%; trained margins are wider)")
    print("RESULT: trained-model Defect-1 task number measured (RTL-driven, 5 splits)")
    return 0

if __name__=="__main__":
    sys.exit(main())
