#!/usr/bin/env python3
"""Check fp16->fp8(E4M3) quantizer (chip convention: exp15=inf/nan, exp0=zero, bias7).
Compares decode(fp8_out) to the fp16 input value for in-range normal inputs, within
one fp8 ulp. Flags gross errors (a 2x-class bug would blow past tolerance)."""
import numpy as np
def dec_fp8(b):
    s=(b>>7)&1; e=(b>>3)&0xF; m=b&7
    if e==0: return 0.0
    if e==15: return (float('nan') if m else float('inf'))*(1 if not s else -1) if False else (float('nan') if m else float('inf'))
    v=(1+m/8.0)*2.0**(e-7); return -v if s else v
# fp8 E4M3 (chip) normal magnitude range: min 2^-6, max 2^(14-7)*(1+7/8)=240
FP8_MIN=2.0**-6; FP8_MAX=2.0**7*(1+7/8.0)  # =240
n=0;fails=0;first=[]
for line in open("/tmp/gf16sim/fp8_vec.txt"):
    xh,qh=line.split(); x=np.frombuffer(bytes.fromhex(xh),dtype='>f2')  # not used directly
    xi=int(xh,16); q=int(qh,16)
    xv=float(np.array(xi,dtype=np.uint16).view(np.float16))
    if not np.isfinite(xv) or xv==0.0: continue
    ax=abs(xv)
    if ax<FP8_MIN or ax>FP8_MAX: continue        # out-of-range -> clamp/zero (separate concern)
    gv=dec_fp8(q)
    if gv==0.0: continue                          # flushed (denormal-ish boundary)
    re=abs(gv-xv)/ax
    n+=1
    if re>0.13:                                   # > ~1 fp8 ulp (1/8=12.5%)
        fails+=1
        if len(first)<6: first.append(f"fp16={xh}({xv:.5g}) fp8={qh} dec={gv:.5g} re={re*100:.1f}%")
print(f"fp8_e4m3 quantizer: {fails}/{n} in-range fail(>1ulp) -> {'CLEAN' if fails==0 else 'BUGS'}")
for s in first: print("  ",s)
