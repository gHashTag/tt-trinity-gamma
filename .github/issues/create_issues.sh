#!/usr/bin/env bash
# create_issues.sh — materialise the γ-side TRI-NET 2026 issue pack as
# real GitHub issues. Safe by default: dry-run unless --confirm is
# passed. Never deletes or edits existing issues.
#
# Usage:
#   bash .github/issues/create_issues.sh [--dry-run] [--confirm]
#                                        [--only PLAN_ID]
#                                        [--repo OWNER/REPO]
#
# Flags:
#   --dry-run        Print what would be created; no API calls. Default.
#   --confirm        Actually call `gh issue create`. Required to mutate.
#   --only PLAN_ID   Operate on a single plan_id (e.g. EN-02) instead
#                    of the whole pack.
#   --repo OWNER/REPO  Target repo. Default: inferred by `gh` from the
#                    current working directory.
#
# R5-honest preamble: the NN_<plan-id>.md filenames in this directory
# encode LOCAL PLAN IDs, NOT GitHub issue numbers. This script prints
# the issue numbers GitHub assigns at creation time; pipe the output
# to a file if you want to record them.
#
# Exit codes:
#   0   success (dry-run or confirmed create completed)
#   1   misuse (bad flag, missing file, etc.)
#   2   tooling missing (gh not on PATH, gh not authenticated)
#   3   confirmation flag missing (refuse to mutate by default)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=1
ONLY=""
REPO_FLAG=""

usage() {
    sed -n '2,30p' "$0"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=1; shift ;;
        --confirm)  DRY_RUN=0; shift ;;
        --only)     ONLY="${2:-}"; shift 2 ;;
        --repo)     REPO_FLAG="--repo ${2:-}"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "unknown flag: $1" >&2; usage; exit 1 ;;
    esac
done

# Tooling check (only required when actually mutating).
if [[ "$DRY_RUN" -eq 0 ]]; then
    if ! command -v gh >/dev/null 2>&1; then
        echo "error: gh (GitHub CLI) not found on PATH" >&2
        exit 2
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "error: gh is not authenticated. Run 'gh auth login' first." >&2
        exit 2
    fi
fi

# Gather files in deterministic order; skip the index/summary itself.
mapfile -t FILES < <(find "$SCRIPT_DIR" -maxdepth 1 -name '[0-9][0-9]_*.md' | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "error: no NN_*.md issue files found under $SCRIPT_DIR" >&2
    exit 1
fi

extract_field() {
    # extract_field <file> <key>  → prints the value, or empty.
    # Portable (mawk-compatible): no 3-arg match().
    local file="$1" key="$2"
    awk -v k="$key" '
        BEGIN { in_fm = 0; pat = "^"k":[[:space:]]*" }
        /^---[[:space:]]*$/ { in_fm = !in_fm; next }
        in_fm == 1 {
            if ($0 ~ pat) {
                v = $0
                sub(pat, "", v)
                # strip leading/trailing double quotes if any
                sub(/^"/, "", v)
                sub(/"$/, "", v)
                print v
                exit
            }
        }
    ' "$file"
}

extract_labels() {
    # extract_labels <file>  → prints labels as a single comma list.
    local file="$1"
    awk '
        BEGIN { in_fm = 0 }
        /^---[[:space:]]*$/ { in_fm = !in_fm; next }
        in_fm == 1 && /^labels:[[:space:]]*\[/ {
            sub(/^labels:[[:space:]]*\[/, "")
            sub(/\][[:space:]]*$/, "")
            gsub(/"/, "")
            gsub(/[[:space:]]/, "")
            print
            exit
        }
    ' "$file"
}

extract_body() {
    # extract_body <file>  → prints everything after the closing `---`.
    awk '
        BEGIN { closed = 0; fm_count = 0 }
        /^---[[:space:]]*$/ {
            fm_count++
            if (fm_count == 2) closed = 1
            next
        }
        closed == 1 { print }
    ' "$1"
}

created_count=0
skipped_count=0

for file in "${FILES[@]}"; do
    plan_id="$(extract_field "$file" plan_id)"
    title="$(extract_field "$file" title)"
    labels="$(extract_labels "$file")"

    if [[ -z "$plan_id" || -z "$title" ]]; then
        echo "warn: $file missing plan_id or title; skipping" >&2
        continue
    fi

    if [[ -n "$ONLY" && "$plan_id" != "$ONLY" ]]; then
        skipped_count=$((skipped_count + 1))
        continue
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[dry-run] would create: plan_id=$plan_id"
        echo "          title:  $title"
        echo "          labels: ${labels:-<none>}"
        echo "          body:   $(extract_body "$file" | wc -l) lines from $(basename "$file")"
        echo
        created_count=$((created_count + 1))
        continue
    fi

    # Real run.
    body_file="$(mktemp)"
    trap 'rm -f "$body_file"' EXIT
    extract_body "$file" > "$body_file"

    label_args=()
    if [[ -n "$labels" ]]; then
        IFS=',' read -r -a lbl_arr <<< "$labels"
        for l in "${lbl_arr[@]}"; do
            [[ -n "$l" ]] && label_args+=(--label "$l")
        done
    fi

    echo "==> creating issue: $plan_id — $title"
    gh issue create $REPO_FLAG \
        --title "$title" \
        --body-file "$body_file" \
        "${label_args[@]}"

    rm -f "$body_file"
    trap - EXIT
    created_count=$((created_count + 1))
done

echo
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "dry-run complete: $created_count issue(s) would be created, $skipped_count skipped"
    echo "re-run with --confirm to actually create them"
    exit 0
fi

echo "done: $created_count issue(s) created, $skipped_count skipped"
exit 0
