# GoldenFloat rung arithmetic — verification finding (2026-06)

## Summary

A semantic cross-check of the `gfN_add` / `gfN_mul` units in `src/` found that
**only GF16 is correct**; every other rung (gf4, gf8, gf12, gf20, gf24, gf32,
gf64, gf128) has a broken add and/or mul. GF16 is the only rung carrying the
`[Verified]` tag (FPGA + MNIST + IGLA RACE); the others are `[Spec] + RTL` and had
never been semantically cross-checked against the float arithmetic they implement.

This was found by `test/gf_arith_xcheck.py` (rung-size-agnostic exponent probe;
exact for every rung, no host-float overflow). The same method **passes GF16**,
which validates the check.

## Per-rung verdict (mantissa=0 exponent probe: 1+1 and 2*1 must give exp = bias+1)

| rung | add | mul | note |
| --- | :-: | :-: | --- |
| gf4   | ❌ | ✅ | add exp wrong |
| gf8   | ❌ | ❌ | add gives 0.5 for 1+1; mul gives 4.0 for 2*1 |
| gf12  | ❌ | ❌ | |
| **gf16** | ✅ | ✅ | the `[Verified]` reference |
| gf20  | ✅ | ❌ | mul off-by-one (half) |
| gf24  | ✅ | ❌ | mul off-by-one (half) |
| gf32  | ✅ | ❌ | mul off-by-one: 1*1 -> 0.5, 2*1 -> 1.0 |
| gf64  | ✅ | ❌ | mul off-by-one |
| gf128 | ✅ | ❌ | mul off-by-one |

A fuller value-domain sweep of gf8 (all 65536 pairs vs an independent
decode->fp32->op->encode reference) showed add 134/256 and mul 148/256 sampled
pairs wrong, with results systematically ~4x too small.

## Root cause (example: `src/gf8_mul.v`)

```
mant_product = {1'b1, mant_a} * {1'b1, mant_b};   // reg [8:0] -- 5b*5b can be 961 (needs 10b) -> TRUNCATION
if (mant_product[8]) exp_product = exp_product + 1; // wrongly bumps exp for products already in [1,2)
... result = {sign, exp_product[2:0], mant_product[3:0]}; // takes wrong mantissa slice (not the bits below the leading 1)
```

`gf8_add` has an analogous error (decrements the exponent in the equal-exponent
normalization branch where it should increment). The bugs differ per rung
(gf20-128 share a consistent mul off-by-one; gf4/8/12 differ), which is why a
single generator pass did not produce them uniformly and only the hand-tuned
GF16 is right.

## Impact

- Affects the `gfN_add`/`gfN_mul` units for all rungs except GF16. These are
  present in the GF4..GF256 RTL set (TT4913 Gamma). Whether they sit on a
  critical compute path of the submitted die should be confirmed; the validated
  compute path is GF16.
- Status: the broken rungs are `[Spec] + RTL`, not `[Verified]` — consistent with
  never having been silicon/MNIST-checked.

## Recommended fix

1. Use GF16's (correct) align/normalize/round logic as the template.
2. Fix one rung at a time, starting with gf8 (8-bit -> full 65536-pair exhaustive
   cross-check feasible), re-running `test/gf_arith_xcheck.py` plus a value-domain
   sweep after each.
3. Treat `gf_arith_xcheck.py` as the regression gate; wire it into CI only once
   all rungs pass (it currently exits non-zero = number of broken rungs).

GF256 is excluded from the probe: its stored exponent bias is itself
`[Open conjecture]` (does not reconcile with `2^(E-1)-1`), a separate issue.
