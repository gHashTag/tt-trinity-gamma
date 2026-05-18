#!/usr/bin/env bash
# create_all_issues.sh — Create all 16 TRI-NET 2026 improvement issues
# Usage after gh auth login: ./create_all_issues.sh

GITHUB_CLI="gh"
REPO="gHashTag/tt-trinity-gamma"
ISSUES_DIR=".github/issues"
TRACKING_FILE="/tmp/issue_numbers_$$"

echo "=========================================="
echo "TRI-NET 2026 — Creating GitHub Issues"
echo "=========================================="
echo ""
echo "Target repository: $REPO"
echo ""

# Check authentication
echo "Checking GitHub CLI authentication..."
if ! $GITHUB_CLI auth status 2>/dev/null | grep -q "Logged in"; then
    echo "❌ ERROR: GitHub CLI not authenticated"
    echo ""
    echo "Please run: gh auth login"
    echo "Then run this script again: ./create_all_issues.sh"
    exit 1
fi
echo "✓ Authenticated as $($GITHUB_CLI api user --jq '.login')"
echo ""

# Clean up tracking file on exit
trap 'rm -f "$TRACKING_FILE"' EXIT

# Read issue files
ISSUES=(
    "00_EPIC_2026.md|epic,priority:high"
    "01_CL01_AR_ML_Coprocessor.md|CLARA,priority:P0,size:medium"
    "02_CL02_Adversarial_Training.md|CLARA,Gap-1,priority:P0,size:small"
    "03_CL03_Crypto_Audit.md|CLARA,Gap-10,priority:P0,size:small"
    "04_CL04_Coq_Export.md|formal-verification,Coq,priority:P1,size:large"
    "05_EN01_Subthreshold_Clock.md|power-efficiency,priority:P0,size:medium"
    "06_EN02_Event_Driven_Compute.md|power-efficiency,neuromorphic,priority:P0,size:medium"
    "07_EN03_Analog_Neuron.md|power-efficiency,analog,research,priority:P1,size:large"
    "08_SN01_Adaptive_LIF.md|neuromorphic,SNN,priority:P1,size:medium"
    "09_SN02_Lateral_Inhibition.md|neuromorphic,cortex,priority:P1,size:medium"
    "10_SN03_STDP_Learning.md|neuromorphic,learning,STDP,priority:P1,size:medium"
    "11_PUB01_Journal_Paper.md|publication,paper,priority:P2,size:large"
    "12_PUB02_Conference_Paper.md|publication,paper,priority:P2,size:medium"
    "13_PUB03_PhD_Dissertation.md|publication,PhD,priority:P2,size:large"
    "14_OS01_t27_Toolchain_v2.md|toolchain,t27,priority:P2,size:large"
    "15_OS02_CI_CD_Community.md|devops,CI-CD,priority:P2,size:small"
    "16_OS03_Python_SDK.md|tooling,Python,SDK,priority:P2,size:medium"
)

echo "Creating 17 issues..."
echo ""
epic_number=""

for issue_info in "${ISSUES[@]}"; do
    IFS='|' read -r file labels_raw <<< "$issue_info"
    # Remove spaces after commas for labels
    labels=$(echo "$labels_raw" | sed 's/, */,/g')
    filepath="$ISSUES_DIR/$file"

    if [[ ! -f "$filepath" ]]; then
        echo "⚠️  WARNING: $filepath not found, skipping"
        continue
    fi

    # Parse title
    title=$(grep -m1 '^title:' "$filepath" | sed 's/^title: *//' | tr -d '"')

    # Extract body (everything after second ---)
    body=$(awk '/^---$/{f++;next} f==2' "$filepath")

    # Check if issue already exists
    existing=$($GITHUB_CLI issue list --repo "$REPO" --state open --search "$title" --json number --jq '.[0].number' 2>/dev/null || echo "")
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        echo "⏭️  Skipping: $title (already exists as #$existing)"
        echo "$file|$existing" >> "$TRACKING_FILE"
        [[ "$file" == "00_EPIC_2026.md" ]] && epic_number="$existing"
        sleep 0.5
        echo ""
        continue
    fi

    # Create issue
    echo "📝 Creating: $title"
    result=$($GITHUB_CLI issue create \
        --repo "$REPO" \
        --title "$title" \
        --body "$body" \
        --label "$labels" \
        --assignee gHashTag 2>&1) || {
        echo "   ✗ Failed to create issue"
        echo "   Error: $result"
        echo "$file|FAILED" >> "$TRACKING_FILE"
        sleep 0.5
        echo ""
        continue
    }

    # Extract issue number
    issue_num=$(echo "$result" | grep -oE '#[0-9]+' | grep -oE '[0-9]+' | head -1)

    if [[ -n "$issue_num" ]]; then
        echo "$file|$issue_num" >> "$TRACKING_FILE"
        echo "   ✓ Created issue #$issue_num"
        [[ "$file" == "00_EPIC_2026.md" ]] && epic_number="$issue_num"
    else
        echo "   ✗ Failed to create issue"
        echo "$file|FAILED" >> "$TRACKING_FILE"
    fi

    sleep 0.5  # Rate limiting
    echo ""
done

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Issues created/checked:"
cat "$TRACKING_FILE" | while IFS='|' read -r file num; do
    if [[ "$num" == "FAILED" ]]; then
        echo "  ✗ $file → FAILED"
    elif [[ "$num" == "null" || -z "$num" ]]; then
        echo "  ⚠️  $file → NOT FOUND"
    else
        echo "  ✓ $file → #$num"
    fi
done
echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
if [[ -n "$epic_number" && "$epic_number" != "FAILED" && "$epic_number" != "null" ]]; then
    echo "1. Review the EPIC issue:"
    echo "   https://github.com/$REPO/issues/$epic_number"
    echo ""
    echo "2. Link all sub-issues to the EPIC #$epic_number"
else
    echo "⚠️  EPIC issue was not created or failed"
fi
echo ""
echo "3. Add dependencies between issues:"
echo "   - Use 'Blocks:' label"
echo "   - Reference other issues in description"
echo ""
echo "✓ Done! Issues are now tracked in GitHub."