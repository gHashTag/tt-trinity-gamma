#!/usr/bin/env bash
# GoldenFloat multiplier verification gate.
# Regenerates the portfolio from the corrected generator and runs every float-
# reference sweep / directed check. Exits non-zero on ANY failure.
# This is the RTL-level differential audit the GF-multiplier erratum calls for.
set -u
cd "$(dirname "$0")"
command -v brew >/dev/null 2>&1 && export PATH="$(brew --prefix)/bin:$PATH"  # macOS only
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fail=0

echo ">> regenerating portfolio (gen_gf_mul.py)"
python3 gen_gf_mul.py >/dev/null || { echo "GEN FAILED"; exit 2; }

run() {  # name  "tb.v dut.v ..."  bad_pattern
  local name="$1" srcs="$2"
  local out
  iverilog -g2012 -o "$WORK/$name.vvp" $srcs 2>"$WORK/$name.cerr" \
    || { echo "  [$name] COMPILE FAIL"; cat "$WORK/$name.cerr"; fail=1; return; }
  out="$(vvp "$WORK/$name.vvp" 2>&1)"
  # Verdict tokens only — NOT the word "fail" which appears in threshold labels like "0/N fail(>8%)".
  if echo "$out" | grep -qiE "BUGS|WRONG|FAILS=[1-9]"; then
    echo "  [$name] FAIL:"; echo "$out" | grep -iE "BUGS|WRONG|FAILS=" | head -4; fail=1
  elif echo "$out" | grep -qiE "CLEAN|ALL [0-9]+ PASS"; then
    echo "  [$name] PASS  ($(echo "$out" | grep -iE 'CLEAN|ALL [0-9]+ PASS' | tail -1))"
  else
    echo "  [$name] FAIL: no positive verdict"; echo "$out" | tail -3; fail=1
  fi
}

echo ">> running sweeps"
run gf8   "gf8_sweep.v gf8_mul_gen.v"
run gf12  "gf12_sweep.v gf12_mul_gen.v"
run gf16  "gf16_sweep.v gf16_mul_gen.v"
run gf20_24_32 "gf_wide2.v gf20_mul_gen.v gf24_mul_gen.v gf32_mul_gen.v"
run gf64_128_256 "gf_big_sanity.v gf64_mul_gen.v gf128_mul_gen.v gf256_mul_gen.v"
run adders_addition "adder_gate.v gf8_add_fixed.v gf12_add_fixed.v"

echo ">> exact-reference random sweep (gf64/128/256 vs Python Fraction)"
mkdir -p /tmp/gf16sim
if iverilog -g2012 -o "$WORK/dump.vvp" gf_wide_dump.v gf64_mul_gen.v gf128_mul_gen.v gf256_mul_gen.v 2>"$WORK/dump.cerr"; then
  vvp "$WORK/dump.vvp" >/dev/null 2>&1
  exout="$(python3 gf_exact_check.py 2>&1)"
  if echo "$exout" | grep -q "ALL BIT-EXACT"; then
    echo "  [gf64/128/256 exact] PASS  ($(echo "$exout" | tail -1))"
  else
    echo "  [gf64/128/256 exact] FAIL:"; echo "$exout" | tail -5; fail=1
  fi
else
  echo "  [gf64/128/256 exact] COMPILE FAIL"; cat "$WORK/dump.cerr"; fail=1
fi

echo ">> quantizer checks (fp8 e4m3 + e5m2-fixed)"
PY="${PYTHON:-$([ -x ../../../openxc7/xrayenv/bin/python ] && echo ../../../openxc7/xrayenv/bin/python || echo python3)}"
if iverilog -g2012 -o "$WORK/q43.vvp" fp8_dump.v fp8_e4m3_quantizer.v 2>"$WORK/q.cerr" \
   && iverilog -g2012 -o "$WORK/q52.vvp" e5m2_dump.v fp8_e5m2_fixed.v 2>>"$WORK/q.cerr"; then
  vvp "$WORK/q43.vvp" >/dev/null 2>&1; vvp "$WORK/q52.vvp" >/dev/null 2>&1
  qout="$($PY fp8_check.py 2>&1; $PY e5m2_check.py 2>&1)"
  if echo "$qout" | grep -qi "BUGS"; then echo "  [quantizers] FAIL:"; echo "$qout"; fail=1
  else echo "  [quantizers] PASS  ($(echo "$qout" | tr '\n' ' '))"; fi
else echo "  [quantizers] COMPILE FAIL"; cat "$WORK/q.cerr"; fail=1; fi

echo
if [ "$fail" -eq 0 ]; then echo "GF AUDIT: ALL PASS ✅ (mul + add + quantizers)"; else echo "GF AUDIT: FAILURES ❌"; fi
exit $fail
