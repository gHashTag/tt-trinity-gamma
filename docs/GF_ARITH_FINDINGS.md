# GoldenFloat rung arithmetic — verification finding (2026-06)

## Summary

A semantic cross-check of the `gfN_add` / `gfN_mul` units in `src/` found that
originally **only GF16 was correct**; every other rung (gf4, gf8, gf12, gf20,
gf24, gf32, gf64, gf128) had a broken add and/or mul. GF16 is the only rung
carrying the `[Verified]` tag (FPGA + MNIST + IGLA RACE); the others are
`[Spec] + RTL` and had never been semantically cross-checked against the float
arithmetic they implement.

This was found by `test/gf_arith_xcheck.py` (rung-size-agnostic exponent probe;
exact for every rung, no host-float overflow). The same method **passes GF16**,
which validates the check.

**Status update (2026-06): GF8 is now fixed and exhaustively verified.** Both
`gf8_add` and `gf8_mul` were rewritten and cross-checked over all 65536 (a,b)
input pairs against an independent value-based reference (`test/gf8_exhaustive.py`):
**65536/65536 pass**, max error **0.719 ULP (add) / 0.500 ULP (mul)** -- i.e.
faithful round-to-nearest. `gf_arith_xcheck.py` now reports 2/9 correct (gf16, gf8).
The remaining seven rungs (gf4, gf12, gf20, gf24, gf32, gf64, gf128) are still
broken and are the next targets.

## Per-rung verdict (mantissa=0 exponent probe: 1+1 and 2*1 must give exp = bias+1)

| rung | add | mul | note |
| --- | :-: | :-: | --- |
| gf4   | ❌ | ✅ | add exp wrong |
| **gf8** | ✅ | ✅ | **FIXED 2026-06** -- 65536/65536 exhaustive, <=1 ULP |
| gf12  | ❌ | ❌ | (was add+mul broken) |
| **gf16** | ✅ | ✅ | the `[Verified]` reference |
| gf20  | ✅ | ❌ | mul off-by-one (half) |
| gf24  | ✅ | ❌ | mul off-by-one (half) |
| gf32  | ✅ | ❌ | mul off-by-one: 1*1 -> 0.5, 2*1 -> 1.0 |
| gf64  | ✅ | ❌ | mul off-by-one |
| gf128 | ✅ | ❌ | mul off-by-one |

The original gf8 was the worst case (both broken): a fuller value-domain sweep
showed add 134/256 and mul 148/256 sampled pairs wrong, results systematically
~4x too small. The fix is described under "GF8 fix" below.

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

## GF8 fix (2026-06, done)

- `gf8_mul`: the implicit-1 mantissa product is now a full 10-bit value (was
  truncated in a `[8:0]` reg); normalize is `prod[9] -> exp+1` else stay, with the
  mantissa taken from the bits just below the leading 1 and guard/round/sticky
  below that; round-to-nearest ties-to-zero, exactly like `gf16_mul`.
- `gf8_add`: significands carry 3 guard bits, alignment captures a sticky bit, the
  post-add leading 1 is found by priority and renormalized, and the 4-bit mantissa
  is rounded to nearest, ties-to-even. (A naive truncating align -- as the wider
  gf16 unit uses -- loses up to ~16 ULP on subtractive cancellation at a 4-bit
  mantissa; the guard bits bring it to < 1 ULP.)
- Verification: `test/gf8_exhaustive.py` drives all 65536 (a,b) pairs through both
  units (iverilog) and compares each result, in ULPs, to an independent value-based
  reference (decode -> exact float -> op). 65536/65536 pass; max error 0.719 ULP
  (add), 0.500 ULP (mul). The reference is non-circular: it checks the produced
  numeric value, not the RTL's bit slicing. Specials (NaN / +-Inf / +-0 / the
  e0m0=zero "0.125 hole" / round-to-Inf at the top binade) are all checked.

## Recommended fix (remaining rungs)

1. Use GF16 / the new GF8 as templates (GF8 is the right template for the small
   rungs: it adds proper guard/sticky rounding that a 4-bit mantissa needs).
2. Fix one rung at a time, re-running `test/gf_arith_xcheck.py` after each, plus --
   for any rung <= 16 bits -- a full exhaustive value-domain sweep modeled on
   `test/gf8_exhaustive.py`.
3. Treat `gf_arith_xcheck.py` as the regression gate; wire it into CI only once
   all rungs pass (it currently exits non-zero = number of broken rungs; now 7).

GF256 is excluded from the probe: its stored exponent bias is itself
`[Open conjecture]` (does not reconcile with `2^(E-1)-1`), a separate issue.
