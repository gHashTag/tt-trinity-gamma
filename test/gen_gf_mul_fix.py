#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# One-shot generator that rewrites the broken gf{20,24,32,64,128}_mul.v units.
#
# The original units shared one bug: mant_product was declared 2 bits too narrow
# (2M bits instead of 2*(M+1)), so the leading bit of the (M+1)x(M+1) significand
# product (at index 2M+1 or 2M) was TRUNCATED and all normalize indices were 2 too
# low; the "carry_out" path also bumped the exponent without incrementing the
# mantissa (doubling the value on rounding). Net effect: products came out ~half
# the correct magnitude (e.g. 1.0*1.0 -> 0.5).
#
# This generator emits a correct unit per rung: full 2(M+1)-bit product, normalize
# (prod[2M+1] -> exp+1 else stay), mantissa = the M bits below the leading 1,
# round-to-nearest ties-to-zero with guard/round/sticky -- the same algorithm as
# the verified gf16_mul / fixed gf8_mul. The special-value prologue and the exact
# special-value constants are preserved verbatim (out of scope here). Verified by
# test/gf_arith_xcheck.py (exponent probe) + test/gf_mul_sweep.py (value sweep).

import os
HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")

# name: (total, E, M). Special-value constants are DERIVED below from the decode
# convention (Inf = exp-all-ones & mant==0; NaN = exp-all-ones & mant!=0), because
# the constants previously hardcoded here were wrong for gf12/20/24/32/64/128 --
# their "Inf" had a nonzero mantissa field, so it actually decoded as NaN and did
# not round-trip. gf8/gf16 (correct) match the derived values exactly.
RUNGS = {
    "gf12":  (12,  4,  7),
    "gf20":  (20,  7, 12),
    "gf24":  (24,  9, 14),
    "gf32":  (32, 12, 19),
    "gf64":  (64, 24, 39),
    "gf128": (128, 48, 79),
    "gf256": (256, 97, 158),
}

def specials(total, E, M):
    """Return (NAN, PINF, NINF, ZERO) as sized Verilog hex literals."""
    emax = (1 << E) - 1
    pinf = emax << M
    sgn  = 1 << (total - 1)
    lit  = lambda v: "%d'h%X" % (total, v)
    return lit(sgn | pinf | 1), lit(pinf), lit(sgn | pinf), lit(0)

TEMPLATE = """// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/{name}_mul.v
// GoldenFloat{total} Multiplication Unit -- [S(1) | E({E}) | M({M})], bias 2^(E-1)-1.
// value = (-1)^S (1 + M/2^{M}) 2^(E-bias).
//
// Rewritten 2026-06 (test/gen_gf_mul_fix.py). The previous version declared
// mant_product 2 bits too narrow ({prodm2} bits, not {prodw}), truncating the leading
// bit of the (M+1)x(M+1) product, and bumped the exponent on rounding without
// incrementing the mantissa -- products came out ~half magnitude (1.0*1.0 -> 0.5).
// This version uses the verified gf16_mul/gf8_mul algorithm: full {prodw}-bit product,
// normalize (prod[{top}] -> exp+1 else stay), mantissa = the {M} bits below the leading
// 1, round-to-nearest ties-to-zero (guard & (round | sticky)). Cross-checked by
// test/gf_arith_xcheck.py and test/gf_mul_sweep.py. Special-value encodings are
// preserved from the original unit (their conformance is a separate question).

`default_nettype none
module {name}_mul (
    input  wire [{hi}:0] a,
    input  wire [{hi}:0] b,
    output reg  [{hi}:0] result
);

    localparam [{esh}:0] EXP_MAX = {emax};
    localparam signed [{esw}:0] BIAS_S    = {bias_s};
    localparam signed [{esw}:0] EXP_MAX_S = {emax_s};

    wire             sign_a = a[{hi}];
    wire [{ehi}:0]   exp_a  = a[{ehia}:{mw}];
    wire [{mhi}:0]   mant_a = a[{mhi}:0];
    wire             sign_b = b[{hi}];
    wire [{ehi}:0]   exp_b  = b[{ehia}:{mw}];
    wire [{mhi}:0]   mant_b = b[{mhi}:0];

    wire is_zero_a = (exp_a == {ez}) && (mant_a == {mz});
    wire is_zero_b = (exp_b == {ez}) && (mant_b == {mz});
    wire is_inf_a  = (exp_a == EXP_MAX) && (mant_a == {mz});
    wire is_inf_b  = (exp_b == EXP_MAX) && (mant_b == {mz});
    wire is_nan_a  = (exp_a == EXP_MAX) && (mant_a != {mz});
    wire is_nan_b  = (exp_b == EXP_MAX) && (mant_b != {mz});

    wire result_sign = sign_a ^ sign_b;

    wire [{phi}:0] full_prod = {{1'b1, mant_a}} * {{1'b1, mant_b}};  // {prodw}-bit

    reg signed [{esw}:0] raw_exp, final_exp;
    reg [{mhi}:0] mant_out, final_mant;
    reg [{mw}:0]  mant_rounded;            // M+1 bits, catches mantissa overflow
    reg           guard, round_b, sticky;

    always @(*) begin
        raw_exp = 0; final_exp = 0; mant_out = 0; final_mant = 0;
        mant_rounded = 0; guard = 0; round_b = 0; sticky = 0;

        if (is_nan_a || is_nan_b)
            result = {NAN};
        else if (is_inf_a && is_zero_b)
            result = {NAN};
        else if (is_inf_b && is_zero_a)
            result = {NAN};
        else if (is_inf_a || is_inf_b)
            result = result_sign ? {NINF} : {PINF};
        else if (is_zero_a || is_zero_b)
            result = {ZERO};
        else begin
            raw_exp = $signed({{2'b00, exp_a}}) + $signed({{2'b00, exp_b}}) - BIAS_S;

            if (full_prod[{top}]) begin                 // product in [2,4) -> exp+1
                raw_exp  = raw_exp + 1;
                mant_out = full_prod[{m2m}:{mp1}];
                guard    = full_prod[{mw}];
                round_b  = full_prod[{mm1}];
                sticky   = |full_prod[{mm2}:0];
            end else begin                              // product in [1,2)
                mant_out = full_prod[{m2mm1}:{mw}];
                guard    = full_prod[{mm1}];
                round_b  = full_prod[{mm2}];
                sticky   = |full_prod[{mm3}:0];
            end

            if (guard && (round_b || sticky))
                mant_rounded = {{1'b0, mant_out}} + 1'b1;
            else
                mant_rounded = {{1'b0, mant_out}};

            if (mant_rounded[{mw}]) begin               // mantissa overflow
                final_exp  = raw_exp + 1;
                final_mant = 0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded[{mhi}:0];
            end

            if (final_exp < 0)
                result = {ZERO};                        // underflow
            else if (final_exp >= EXP_MAX_S)
                result = result_sign ? {NINF} : {PINF};  // overflow
            else if (final_exp == 0 && final_mant == {mz})
                result = {ZERO};                        // exp0/mant0 is the zero code
            else
                result = {{result_sign, final_exp[{ehi}:0], final_mant}};
        end
    end

endmodule
"""

def build(name, total=None, E=None, M=None):
    """Return the Verilog text for a rung. Params override RUNGS (for variants)."""
    if total is None:
        total, E, M = RUNGS[name]
    NAN, PINF, NINF, ZERO = specials(total, E, M)
    W = M + 1
    return TEMPLATE.format(
        name=name, total=total, E=E, M=M,
        hi=total - 1, ehi=E - 1, mhi=M - 1, mw=M,
        ehia=total - 2, esh=E - 1, esw=E + 1,
        emax=(2 ** E - 1), bias=(2 ** (E - 1) - 1),
        bias_s="%d'sd%d" % (E + 2, 2 ** (E - 1) - 1),
        emax_s="%d'sd%d" % (E + 2, 2 ** E - 1),
        ez="%d'd0" % E, mz="%d'd0" % M,
        phi=2 * M + 1, prodw=2 * W, prodm2=2 * W - 2, top=2 * M + 1,
        m2m=2 * M, mp1=M + 1, mm1=M - 1, mm2=M - 2, mm3=M - 3, m2mm1=2 * M - 1,
        NAN=NAN, PINF=PINF, NINF=NINF, ZERO=ZERO,
    )

def emit(name):
    f = build(name)
    path = os.path.join(SRC, name + "_mul.v")
    with open(path, "w") as fh:
        fh.write(f)
    print("wrote", path)

if __name__ == "__main__":
    for n in RUNGS:
        emit(n)
