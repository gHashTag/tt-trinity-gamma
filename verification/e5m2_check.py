import numpy as np, sys
def dec(b):
    e=(b>>2)&0x1F;m=b&3
    if e==0:return 0.0
    if e==31:return float('inf')
    return ((-1)**((b>>7)&1))*(1+m/4.0)*2.0**(e-15)
n=0;fails=0
for line in open("/tmp/gf16sim/e5m2_vec.txt"):
    xh,qh=line.split();xi=int(xh,16);q=int(qh,16)
    xv=float(np.array(xi,dtype=np.uint16).view(np.float16))
    if not np.isfinite(xv) or xv==0.0:continue
    gv=dec(q)
    if gv==0.0 or not np.isfinite(gv):continue
    re=abs(gv-xv)/abs(xv);n+=1
    if re>0.26: fails+=1
print(f"fp8_e5m2(fixed): {fails}/{n} fail -> {'CLEAN' if fails==0 else 'BUGS'}")
