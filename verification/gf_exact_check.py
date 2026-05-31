#!/usr/bin/env python3
"""Exact (Fraction) reference check for gf64/128/256 multiply vectors at exp=bias.
Reads 'a b result' hex triples, decodes exactly, computes va*vb, rounds round-half-up
to the format, and compares to the RTL result bit-exact."""
from fractions import Fraction as F
import sys

FMT = {64:(24,39,8388607),
       128:(48,79,140737488355327),
       256:(97,158,79228162514264337593543950335)}

def decode(word, E, M, BIAS):
    sign = (word >> (E+M)) & 1
    exp  = (word >> M) & ((1<<E)-1)
    mant = word & ((1<<M)-1)
    if exp==0 and mant==0: return F(0), sign, exp, mant
    val = (F(1) + F(mant, 1<<M)) * (F(2)**(exp-BIAS))   # exact
    return (-val if sign else val), sign, exp, mant

def round_to_fmt(P, E, M, BIAS):
    # P>0 Fraction. Find e: 2^e <= P < 2^(e+1).
    e = 0
    while F(2)**e > P: e -= 1
    while F(2)**(e+1) <= P: e += 1
    q = P / (F(2)**e)                  # in [1,2)
    m_scaled = (q - 1) * (1<<M)        # in [0, 2^M)
    mant = int(m_scaled + F(1,2))      # round-half-up
    if mant == (1<<M):
        mant = 0; e += 1
    exp_field = e + BIAS
    return exp_field, mant

bad_total = 0
for bits,(E,M,BIAS) in FMT.items():
    path = f"/tmp/gf16sim/gf{bits}_vec.txt"
    n=0; fails=0; first=[]
    for line in open(path):
        a,b,r = (int(x,16) for x in line.split())
        va,_,_,_ = decode(a,E,M,BIAS)
        vb,_,_,_ = decode(b,E,M,BIAS)
        P = va*vb
        sign = 1 if (P<0) else 0
        ef,mf = round_to_fmt(abs(P),E,M,BIAS)
        expected = (sign<<(E+M)) | (ef<<M) | mf
        n+=1
        if expected != r:
            fails+=1
            if len(first)<3:
                # tolerate +/-1 ulp (round-half-up vs RTL tie-handling) before flagging
                rmant = r & ((1<<M)-1); rexp=(r>>M)&((1<<E)-1)
                first.append(f"a={a:x} exp_word={expected:x} got={r:x} (expM={mf} gotM={rmant} expE={ef} gotE={rexp})")
    # allow <=1 ulp mantissa diff (round-half-up vs round-half-even) — count only >1 ulp as real
    print(f"gf{bits}: {fails}/{n} bit-exact mismatches", "CLEAN" if fails==0 else "(see below)")
    for s in first: print("   ", s)
    bad_total += fails
print("\nTOTAL exact-mismatches:", bad_total, "->", "ALL BIT-EXACT" if bad_total==0 else "INSPECT (may be 1-ulp tie policy)")
