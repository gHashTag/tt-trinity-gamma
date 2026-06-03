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

**Status update (2026-06): 7/9 rungs now fixed and verified.**
- **GF8** (`gf8_add` + `gf8_mul`): rewritten and cross-checked over all 65536 (a,b)
  pairs vs an independent value-based reference (`test/gf8_exhaustive.py`):
  65536/65536 pass, max 0.719 ULP (add) / 0.500 ULP (mul).
- **GF20/24/32/64/128 mul** (`test/gen_gf_mul_fix.py`): the five shared a single
  width bug -- `mant_product` declared `2M` bits instead of `2(M+1)`, truncating
  the leading product bit, plus a rounding path that bumped the exponent without
  incrementing the mantissa. All five rewritten with the verified algorithm and
  cross-checked: exponent probe OK, and `test/gf_mul_sweep.py` runs 7200
  finite-normal pairs/rung against an EXACT-RATIONAL reference (needed because
  gf64/gf128 overflow IEEE double) -- max 0.500 ULP on every rung.

`gf_arith_xcheck.py` now reports **7/9 correct** (gf8, gf16, gf20, gf24, gf32,
gf64, gf128). Remaining: **gf4** (add) and **gf12** (add+mul).

## Per-rung verdict (mantissa=0 exponent probe: 1+1 and 2*1 must give exp = bias+1)

| rung | add | mul | note |
| --- | :-: | :-: | --- |
| gf4   | ❌ | ✅ | add exp wrong |
| **gf8** | ✅ | ✅ | **FIXED 2026-06** -- 65536/65536 exhaustive, <=1 ULP |
| gf12  | ❌ | ❌ | still broken (add+mul) -- next target |
| **gf16** | ✅ | ✅ | the `[Verified]` reference |
| **gf20** | ✅ | ✅ | **mul FIXED 2026-06** -- sweep 0.5 ULP |
| **gf24** | ✅ | ✅ | **mul FIXED 2026-06** -- sweep 0.5 ULP |
| **gf32** | ✅ | ✅ | **mul FIXED 2026-06** (was 1*1 -> 0.5) |
| **gf64** | ✅ | ✅ | **mul FIXED 2026-06** -- sweep 0.5 ULP |
| **gf128**| ✅ | ✅ | **mul FIXED 2026-06** -- sweep 0.5 ULP |

The original gf8 was the worst case (both broken): a fuller value-domain sweep
showed add 134/256 and mul 148/256 sampled pairs wrong, results systematically
~4x too small. The fixes are described under "GF8 fix" and "GF20-128 mul fix" below.

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

## GF20-128 mul fix (2026-06, done)

All five units shared one bug: `mant_product` was declared `2M` bits wide instead
of `2*(M+1)`, so the leading bit of the `(M+1)x(M+1)` significand product (at index
`2M+1` or `2M`) was truncated and the normalize indices were all 2 too low; the
`carry_out` path also bumped the exponent on rounding without incrementing the
mantissa. Net effect: products came out ~half magnitude (gf32 `1.0*1.0 -> 0.5`).

`test/gen_gf_mul_fix.py` regenerates all five with the verified gf16/gf8 algorithm:
full `2(M+1)`-bit product; normalize `prod[2M+1] -> exp+1` else stay; mantissa = the
`M` bits below the leading 1; round-to-nearest ties-to-zero with guard/round/sticky.
The special-value prologue and constants are preserved verbatim (their conformance
is a separate question). Verified by the exponent probe + `test/gf_mul_sweep.py`
(7200 finite-normal pairs/rung vs an exact-rational reference; max 0.5 ULP each).

## Recommended fix (remaining rungs)

1. Use GF16 / the new GF8 as templates (GF8 is the right template for the small
   rungs: it adds proper guard/sticky rounding that a 4-bit mantissa needs).
2. Remaining: **gf4** (add) and **gf12** (add+mul). gf4 and gf12 are <= 12 bits, so
   gf4 is exhaustively checkable and gf12 nearly so (2^24 mul pairs; sampled add).
   Re-run `test/gf_arith_xcheck.py` after each.
3. Treat `gf_arith_xcheck.py` as the regression gate; wire it into CI only once
   all rungs pass (it currently exits non-zero = number of broken rungs; now 2).

GF256 is excluded from the probe: its stored exponent bias is itself
`[Open conjecture]` (does not reconcile with `2^(E-1)-1`), a separate issue.
