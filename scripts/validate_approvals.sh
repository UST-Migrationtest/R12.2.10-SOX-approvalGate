#!/usr/bin/env bash
# =============================================================================
# validate_approvals.sh
# Purpose : Validates PR approval count and SoD compliance via GitHub API.
#           Returns exit code 0 (compliant) or 1 (non-compliant).
# Usage   : validate_approvals.sh --repo <owner/repo> --pr <number>
#                                 --min-approvals <N> --author <username>
# =============================================================================
set -euo pipefail

REPO=""
PR_NUMBER=""
MIN_APPROVALS=2
PR_AUTHOR=""
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)           REPO="$2";          shift 2 ;;
    --pr)             PR_NUMBER="$2";     shift 2 ;;
    --min-approvals)  MIN_APPROVALS="$2"; shift 2 ;;
    --author)         PR_AUTHOR="$2";     shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" || -z "$PR_NUMBER" ]]; then
  echo "ERROR: --repo and --pr are required" >&2
  exit 1
fi

if [[ -z "$GH_TOKEN" ]]; then
  echo "ERROR: GH_TOKEN or GITHUB_TOKEN environment variable must be set" >&2
  exit 1
fi

echo "=== Validating PR Approvals ==="
echo "Repository  : $REPO"
echo "PR Number   : $PR_NUMBER"
echo "PR Author   : $PR_AUTHOR"
echo "Min Required: $MIN_APPROVALS"
echo ""

# Fetch reviews from GitHub API
REVIEWS_JSON=$(curl -sf \
  -H "Authorization: token $GH_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${REPO}/pulls/${PR_NUMBER}/reviews")

# Parse unique approvers (Python for reliability)
RESULT=$(echo "$REVIEWS_JSON" | python3 - <<'PYEOF'
import sys, json

reviews = json.load(sys.stdin)
approved_users = set()
pr_author = "##PR_AUTHOR##"

for review in reviews:
    if review.get("state") == "APPROVED":
        approved_users.add(review["user"]["login"])

approver_list = list(approved_users)
approval_count = len(approver_list)

# SoD check
sod_violation = pr_author in approved_users if pr_author else False

print(json.dumps({
    "approval_count": approval_count,
    "approvers": approver_list,
    "sod_violation": sod_violation
}))
PYEOF
)

# Substitute PR_AUTHOR into the Python script properly
RESULT=$(echo "$REVIEWS_JSON" | python3 -c "
import sys, json
reviews = json.load(sys.stdin)
approved_users = set()
pr_author = '${PR_AUTHOR}'
for review in reviews:
    if review.get('state') == 'APPROVED':
        approved_users.add(review['user']['login'])
approver_list = list(approved_users)
approval_count = len(approver_list)
sod_violation = pr_author in approved_users if pr_author else False
print(json.dumps({'approval_count': approval_count, 'approvers': approver_list, 'sod_violation': sod_violation}))
")

APPROVAL_COUNT=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['approval_count'])")
APPROVERS=$(echo "$RESULT" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['approvers']))")
SOD=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['sod_violation'])")

echo "Approval Count : $APPROVAL_COUNT"
echo "Approvers      : $APPROVERS"
echo "SoD Violation  : $SOD"
echo ""

FAILED=0

# SoD check
if [[ "$SOD" == "True" || "$SOD" == "true" ]]; then
  echo "FAIL: Segregation of Duties violation — PR author '$PR_AUTHOR' is listed as an approver"
  FAILED=1
fi

# Minimum approval count
if [[ "$APPROVAL_COUNT" -lt "$MIN_APPROVALS" ]]; then
  echo "FAIL: Insufficient approvals — got $APPROVAL_COUNT, need $MIN_APPROVALS"
  FAILED=1
fi

if [[ $FAILED -eq 0 ]]; then
  echo "PASS: $APPROVAL_COUNT approvals, no SoD violations — SOX compliant"
fi

exit $FAILED
