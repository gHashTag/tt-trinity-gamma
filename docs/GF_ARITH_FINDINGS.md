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

- **GF12** (`gf12_add` + `gf12_mul`): mul had the same width bug as gf20-128
  (`mant_product` `[14:0]` not `[15:0]`); add had a too-narrow `final_exp` so the
  underflow test flushed every valid exponent >= 8 to zero (1.0+1.0 -> exp 8 -> 0).
  Both regenerated (add via `gen_gf_add_fix.py`, mul via `gen_gf_mul_fix.py`) and
  cross-checked: probe OK, mul sweep 0.500 ULP, add sweep 0.625 ULP.
- **GF4** (`gf4_add` + `gf4_mul`): degenerate format (bias 0 -> only finite
  exponent is 0; representable set {+-0,+-1.25,+-1.5,+-1.75,+-Inf,NaN}, 1.0 is a
  hole). `gf4_mul` had been a non-float toy (`mant_a+mant_b`) with an is_inf test
  aliased to zero. Both rewritten as round-to-nearest into that grid and verified
  EXHAUSTIVELY (256/256 pairs) by `test/gf4_exhaustive.py`. The exponent probe
  cannot test gf4 (its "1.0 = exp=bias" collides with the zero code), so it now
  skips bias-0 rungs and gf4 relies on the exhaustive test.

**The whole ladder is now verified.** `gf_arith_xcheck.py` reports **8/8 probed
rungs correct** (gf8, gf12, gf16, gf20, gf24, gf32, gf64, gf128) and gf4 passes
its 256/256 exhaustive check. A CI job (`goldenfloat-arith` in
`.github/workflows/test.yaml`) runs the probe + both exhaustive checks + both
value sweeps on every push.

### Caveat: gf16_add legacy imprecision (not fixed)
The value sweep also revealed that **gf16_add** -- the silicon-`[Verified]` rung --
is itself imprecise: its truncating alignment loses the guard bit, so e.g.
`0.5009765625 + (-1.0)` returns `-0.5` instead of the exactly-representable
`-0.4990234375` (`0xbbfe`), up to ~512 ULP on cancellation. The fixed gf8/gf12
add units use guard/round/sticky and stay < 1 ULP, i.e. they are MORE accurate
than the reference rung. gf16 is left untouched here because it is the
silicon-validated unit; bringing it onto the guard/round/sticky path (it can reuse
`gen_gf_add_fix.py`) is a candidate follow-up.

## Per-rung verdict (mantissa=0 exponent probe: 1+1 and 2*1 must give exp = bias+1)

| rung | add | mul | note |
| --- | :-: | :-: | --- |
| **gf4**  | ✅ | ✅ | **FIXED 2026-06** -- 256/256 exhaustive (degenerate fmt) |
| **gf8** | ✅ | ✅ | **FIXED 2026-06** -- 65536/65536 exhaustive, <=1 ULP |
| **gf12** | ✅ | ✅ | **FIXED 2026-06** -- add 0.625 ULP, mul 0.5 ULP |
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

## Special-value (Inf/NaN/overflow) fix (2026-06, done)

A follow-up audit found the rung units' Inf/NaN *constants* were wrong on
gf12/20/24/32/64/128: the emitted "Inf" had a nonzero mantissa field, so by the
decode convention (`Inf = exp-all-ones & mant==0`) it actually decoded as NaN and
did not round-trip -- i.e. overflow produced a NaN-shaped value. (gf4/gf8/gf16 were
already correct.) Additionally the gf20-128 *add* units still carried those wrong
constants and gf64/gf128 add mis-handled overflow.

Fix: both generators now DERIVE the special constants from `(W,E,M)`
(`PINF=EXP_MAX<<M`, `NINF=sign|PINF`, `NaN=sign|PINF|1`), and all `[Spec]` add
units (gf12/20/24/32/64/128) were regenerated with the verified GRS algorithm.
New `test/gf_specials.py` drives Inf/NaN/overflow through every rung and checks the
result decodes to the right kind (and that overflow rounds to a *round-trippable*
Inf). All rungs pass; the add value sweep now also covers gf20-128 (<= 0.667 ULP).

### Caveat: gf16_mul latent overflow (informational, not fixed)
The specials check also shows gf16_mul flushes a very-large product to **zero**
instead of Inf (its `final_exp[6]` test aliases a large positive exponent to the
underflow path). Like the gf16_add imprecision, this is never exercised by
near-1.0 workloads; gf16 is the silicon-`[Verified]` rung and is left untouched
(its source must match the fabricated die). `gf_specials.py` reports gf16's
overflow cases as INFORMATIONAL.

## Status: ladder complete; follow-ups

All gf4..gf128 add/mul units are now fixed and verified, and the suite is a CI gate
(`goldenfloat-arith`). Two open items remain, both orthogonal to the datapath:

1. **gf16_add legacy imprecision** (see caveat above) -- reuse `gen_gf_add_fix.py`
   to bring the silicon-`[Verified]` rung onto the guard/round/sticky path, if a
   re-validation of that rung is in scope.
2. **GF256 bias open conjecture** -- its stored exponent bias does not reconcile
   with `2^(E-1)-1`; pin the convention from the t27 spec before cross-checking it.
3. **gfN special-value encodings** -- DONE (see "Special-value fix" above); only
   gf16's latent mul-overflow remains, deferred with gf16_add as a silicon caveat.

GF256 is excluded from the probe: its stored exponent bias is itself
`[Open conjecture]` (does not reconcile with `2^(E-1)-1`), a separate issue.
