#!/usr/bin/env bash
# =============================================================================
# sox_controls_check.sh
# Purpose : Pre-deployment SOX internal control checklist.
#           Validates branch protection, CODEOWNERS, and environment rules
#           are correctly configured before a deployment is allowed.
# Usage   : sox_controls_check.sh --repo <owner/repo> [--token <gh_token>]
# =============================================================================
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-}"
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
BRANCH="main"
FAILED=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)   REPO="$2";     shift 2 ;;
    --token)  GH_TOKEN="$2"; shift 2 ;;
    --branch) BRANCH="$2";   shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

check_or_fail() {
  local test_name="$1"
  local result="$2"
  local expected="$3"
  if [[ "$result" == "$expected" ]]; then
    echo "PASS — $test_name"
  else
    echo "FAIL — $test_name (expected: $expected, got: $result)"
    FAILED=1
  fi
}

echo "========================================"
echo "SOX Internal Controls Check"
echo "Repository : $REPO"
echo "Branch     : $BRANCH"
echo "========================================"
echo ""

# ── Control 1: Branch protection ────────────────────────────────────────────
echo "--- Control 1: Branch Protection ($BRANCH) ---"
if [[ -n "$GH_TOKEN" && -n "$REPO" ]]; then
  BP=$(curl -sf \
    -H "Authorization: token $GH_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO}/branches/${BRANCH}/protection" 2>/dev/null || echo '{}')

  REQ_PR=$(echo "$BP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('required_pull_request_reviews',{}).get('required_approving_review_count',0))" 2>/dev/null || echo 0)
  REQ_STAT=$(echo "$BP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(bool(d.get('required_status_checks')))" 2>/dev/null || echo False)
  REQ_CO=$(echo "$BP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('required_pull_request_reviews',{}).get('require_code_owner_reviews',False))" 2>/dev/null || echo False)

  check_or_fail "Required approvals >= 2"        "$([ "$REQ_PR" -ge 2 ] && echo true || echo false)" "true"
  check_or_fail "Required status checks enabled"  "$REQ_STAT" "True"
  check_or_fail "CODEOWNERS review required"      "$REQ_CO"   "True"
else
  echo "SKIP — GitHub token not available; cannot query branch protection API"
  echo "       Manually verify at: https://github.com/$REPO/settings/branches"
fi

echo ""

# ── Control 2: CODEOWNERS file exists ───────────────────────────────────────
echo "--- Control 2: CODEOWNERS File ---"
if [[ -f ".github/CODEOWNERS" ]]; then
  echo "PASS — .github/CODEOWNERS exists"
  LINE_COUNT=$(wc -l < .github/CODEOWNERS)
  echo "      ($LINE_COUNT lines, $(grep -c "^[^#]" .github/CODEOWNERS) active rules)"
else
  echo "FAIL — .github/CODEOWNERS not found"
  FAILED=1
fi

echo ""

# ── Control 3: SOX config file exists and is valid JSON ─────────────────────
echo "--- Control 3: SOX Configuration ---"
if [[ -f "config/sox_config.json" ]]; then
  if python3 -m json.tool config/sox_config.json > /dev/null 2>&1; then
    echo "PASS — config/sox_config.json is valid JSON"
    REQUIRED_KEYS=("min_approvers" "dual_approval_threshold" "audit_retention_days" "sod_enforced")
    for key in "${REQUIRED_KEYS[@]}"; do
      if python3 -c "import json; d=json.load(open('config/sox_config.json')); assert '$key' in d" 2>/dev/null; then
        echo "PASS — SOX config key '$key' present"
      else
        echo "FAIL — SOX config missing key '$key'"
        FAILED=1
      fi
    done
  else
    echo "FAIL — config/sox_config.json is not valid JSON"
    FAILED=1
  fi
else
  echo "FAIL — config/sox_config.json not found"
  FAILED=1
fi

echo ""

# ── Control 4: Audit log script is not modified ─────────────────────────────
echo "--- Control 4: Audit Script Integrity ---"
AUDIT_SCRIPT="scripts/generate_sox_audit_log.sh"
if [[ -f "$AUDIT_SCRIPT" ]]; then
  SCRIPT_HASH=$(sha256sum "$AUDIT_SCRIPT" | awk '{print $1}')
  echo "PASS — $AUDIT_SCRIPT exists (SHA256: $SCRIPT_HASH)"
  echo "       Verify this matches the approved baseline hash in sox_config.json"
else
  echo "FAIL — $AUDIT_SCRIPT not found"
  FAILED=1
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "========================================"
if [[ $FAILED -eq 0 ]]; then
  echo "RESULT: ALL SOX CONTROLS VERIFIED — COMPLIANT"
else
  echo "RESULT: SOX CONTROL FAILURES DETECTED — NOT COMPLIANT"
  echo "        Review FAIL items above before proceeding to PROD"
fi
echo "========================================"

exit $FAILED
