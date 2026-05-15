#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# check_no_star.sh — R-SI-1 CI gate for tt-trinity-max-true
#
# Purpose:
#   Fail CI if any NEW `*` (multiplication) token appears in synthesisable
#   RTL files under src/*.v in a pull request diff, outside the single
#   grandfathered exception: src/gf16_mul.v (GF(16) Karatsuba, pre-approved
#   in trinity-fpga#61).
#
# Rule R-SI-1 rationale:
#   Area and timing budgets at 50 MHz / SKY130A are extremely tight.
#   Unmapped `*` operators synthesise to full parallel multipliers (~200–600
#   cells each) and blow the area/WNS targets.  All new arithmetic must use
#   explicit LUT structures or pre-approved GF modules.
#
# Exclusions applied to each added line in the diff:
#   - src/gf16_mul.v        — grandfathered; GF(16) Karatsuba, no DSP risk
#   - Lines after //        — single-line comment remainder
#   - (* ... *) attributes  — Yosys synthesis attribute syntax
#   - always @(*) / @*      — sensitivity list wildcards (not arithmetic)
#
# Output (R5-honest):
#   PASS  → exit 0   prints "R-SI-1 PASS: no new * operators found."
#   FAIL  → exit 1   prints each offending added line + FAIL banner
#
# Usage:
#   bash tools/check_no_star.sh                     # diff vs origin/main (default)
#   bash tools/check_no_star.sh --diff origin/main  # explicit base ref
#   bash tools/check_no_star.sh --full              # full-scan audit mode (exit 0)
#   bash tools/check_no_star.sh src/                # legacy positional — runs diff mode
#
# Author: Vasilev Dmitrii <admin@t27.ai>
# Refs:   trinity-fpga#94 (Lane U pre-registration), #61 (R-SI-1 origin),
#         trinity-fpga#93
# -----------------------------------------------------------------------

set -euo pipefail

GRANDFATHERED="gf16_mul.v"
MODE="diff"
BASE_REF="origin/main"

# --- argument parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --diff)
            MODE="diff"
            if [[ $# -gt 1 && "$2" != --* ]]; then
                BASE_REF="$2"; shift
            fi
            shift
            ;;
        --full)
            MODE="full"
            shift
            ;;
        src/|src)
            # Legacy positional argument — ignore, use diff mode
            shift
            ;;
        *)
            # Any other argument: treat as base ref for diff mode
            BASE_REF="$1"
            shift
            ;;
    esac
done

echo "R-SI-1 check_no_star [mode=${MODE}] (grandfathered: ${GRANDFATHERED})"
echo "--------------------------------------------------------------------"

# Shared filter pipeline — applied to raw grep/diff output
# Removes:
#   1. Grandfathered file
#   2. Lines where * follows // (single-line comment context)
#   3. (* ... *) synthesis attribute lines
#   4. always @(*) / always @* sensitivity list lines
filter_star_lines() {
    grep -v "${GRANDFATHERED}" \
    | grep -vE '\(\*[^)]*\)' \
    | grep -vE '@\s*\(\s*\*\s*\)' \
    | grep -vE '@\s*\*' \
    || true
}

if [[ "${MODE}" == "diff" ]]; then
    # Fetch base ref if in a shallow CI clone
    git fetch origin main --depth=1 2>/dev/null || true

    HITS=$(git diff "${BASE_REF}" -- 'src/*.v' \
        | grep '^+' \
        | grep -v '^+++' \
        | grep -E '\*' \
        | grep -v '//.*\*' \
        | sed 's/^+/ADDED: /' \
        | filter_star_lines \
        || true)

    if [[ -z "${HITS}" ]]; then
        echo "R-SI-1 PASS: no new * operators found in diff vs ${BASE_REF}."
        exit 0
    else
        echo "R-SI-1 FAIL: new * operator(s) detected in diff vs ${BASE_REF}:"
        echo "${HITS}"
        echo "--------------------------------------------------------------------"
        echo "R-SI-1 FAIL: remove the above before merging. See trinity-fpga#61."
        exit 1
    fi

else
    # --full mode: scan entire src/*.v — audit-only, always exits 0
    # (pre-existing * operators in baseline are listed as INFO, not violations)
    HITS=$(grep -nE '\*' src/*.v 2>/dev/null \
        | grep -v "${GRANDFATHERED}" \
        | grep -v '^[^:]*:[^:]*:.*//.*\*' \
        | grep -vE '^[^:]*:[^:]*:[[:space:]]*\*' \
        | filter_star_lines \
        || true)

    if [[ -z "${HITS}" ]]; then
        echo "R-SI-1 PASS (full scan): no * operators found outside grandfathered files."
    else
        echo "R-SI-1 INFO (full scan — pre-existing hits listed for audit only):"
        echo "${HITS}"
        echo "--------------------------------------------------------------------"
        echo "R-SI-1 NOTE: full-scan mode is audit-only. Use default (diff) mode for CI gating."
    fi
    exit 0
fi
