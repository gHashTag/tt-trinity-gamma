#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Generate CORRECTED gf16 add/mul as SEPARATE next-gen modules (gf16_v2_add,
# gf16_v2_mul) without touching the silicon-[Verified] gf16_add.v / gf16_mul.v.
# The fabricated TT4913 die uses the original gf16 units, so their source must
# stay byte-for-byte as taped out (provenance). These v2 modules are the corrected
# candidate for a future tapeout: faithful round-to-nearest add (guard/round/sticky
# instead of the truncating alignment that costs up to ~512 ULP on cancellation)
# and a mul with correct overflow (the original flushes very-large products to zero
# because final_exp[6] aliases overflow to the underflow path).
#
# Verified by test/gf16_v2_verify.py (sweep + specials + old-vs-new quantification).
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "..", "src")
sys.path.insert(0, HERE)
import gen_gf_add_fix as A
import gen_gf_mul_fix as M

GF16 = (16, 6, 9)   # total, E, M

def main():
    # ADD: inject a private rung name so the generator emits module gf16_v2_add.
    A.RUNGS["gf16_v2"] = GF16
    add_txt = A.emit("gf16_v2", write=False)
    with open(os.path.join(SRC, "gf16_v2_add.v"), "w") as f:
        f.write(add_txt)
    print("wrote src/gf16_v2_add.v")

    # MUL: build with explicit params -> module gf16_v2_mul.
    mul_txt = M.build("gf16_v2", *GF16)
    with open(os.path.join(SRC, "gf16_v2_mul.v"), "w") as f:
        f.write(mul_txt)
    print("wrote src/gf16_v2_mul.v")

if __name__ == "__main__":
    main()
