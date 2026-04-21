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
SHA=""
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)           REPO="$2";          shift 2 ;;
    --pr)             PR_NUMBER="$2";     shift 2 ;;
    --sha)            SHA="$2";           shift 2 ;;
    --min-approvals)  MIN_APPROVALS="$2"; shift 2 ;;
    --author)         PR_AUTHOR="$2";     shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "ERROR: --repo is required" >&2
  exit 1
fi

if [[ -z "$PR_NUMBER" && -z "$SHA" ]]; then
  echo "ERROR: --pr or --sha is required" >&2
  exit 1
fi

if [[ -z "$GH_TOKEN" ]]; then
  echo "ERROR: GH_TOKEN or GITHUB_TOKEN environment variable must be set" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# If invoked with --sha (post-merge PROD path), resolve the PR number first
# ---------------------------------------------------------------------------
if [[ -n "$SHA" && -z "$PR_NUMBER" ]]; then
  echo "=== Resolving PR for commit $SHA ==="
  PR_SEARCH=$(curl -s \
    -H "Authorization: token $GH_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO}/commits/${SHA}/pulls")

  if [[ -z "$PR_SEARCH" || "$PR_SEARCH" == "null" ]]; then
    echo "ERROR: Could not resolve PR for commit $SHA"
    exit 1
  fi

  PR_NUMBER=$(echo "$PR_SEARCH" | python3 -c "
import sys, json
try:
    prs = json.load(sys.stdin)
    if not prs:
        print('')
    else:
        print(prs[0]['number'])
except Exception:
    print('')
")

  if [[ -z "$PR_NUMBER" ]]; then
    echo "ERROR: No PR found linked to commit $SHA — PROD deploy blocked"
    exit 1
  fi

  # Also resolve the PR author if not provided
  if [[ -z "$PR_AUTHOR" ]]; then
    PR_AUTHOR=$(echo "$PR_SEARCH" | python3 -c "
import sys, json
try:
    prs = json.load(sys.stdin)
    print(prs[0]['user']['login'] if prs else '')
except Exception:
    print('')
")
  fi

  echo "Resolved PR #$PR_NUMBER (author: $PR_AUTHOR)"
  echo ""
fi

echo "=== Validating PR Approvals ==="
echo "Repository  : $REPO"
echo "PR Number   : $PR_NUMBER"
echo "PR Author   : $PR_AUTHOR"
echo "Min Required: $MIN_APPROVALS"
echo ""

# ---------------------------------------------------------------------------
# Fetch reviews from GitHub API
# NOTE: Using -s (silent) WITHOUT -f so we capture error responses as JSON
# ---------------------------------------------------------------------------
HTTP_CODE_FILE=$(mktemp)
REVIEWS_JSON=$(curl -s -w "%{http_code}" -o - \
  -H "Authorization: token $GH_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${REPO}/pulls/${PR_NUMBER}/reviews") || true

# Extract HTTP status code from the end of the response
HTTP_CODE="${REVIEWS_JSON: -3}"
REVIEWS_JSON="${REVIEWS_JSON:0:${#REVIEWS_JSON}-3}"
rm -f "$HTTP_CODE_FILE"

# Guard: validate we got a usable response
if [[ -z "$REVIEWS_JSON" ]]; then
  echo "ERROR: GitHub API returned empty response (HTTP $HTTP_CODE)"
  echo "       Check that GH_TOKEN has 'pull-requests: read' permission"
  exit 1
fi

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "ERROR: GitHub API returned HTTP $HTTP_CODE"
  echo "Response: $REVIEWS_JSON"
  exit 1
fi

# ---------------------------------------------------------------------------
# Parse unique approvers
# ---------------------------------------------------------------------------
RESULT=$(echo "$REVIEWS_JSON" | python3 -c "
import sys, json

try:
    reviews = json.load(sys.stdin)
except json.JSONDecodeError as e:
    print(json.dumps({'error': f'Failed to parse reviews JSON: {e}'}))
    sys.exit(1)

if not isinstance(reviews, list):
    print(json.dumps({'error': 'Expected a list of reviews from the API'}))
    sys.exit(1)

approved_users = set()
pr_author = '${PR_AUTHOR}'

for review in reviews:
    if review.get('state') == 'APPROVED':
        approved_users.add(review['user']['login'])

approver_list = sorted(approved_users)
approval_count = len(approver_list)
sod_violation = pr_author in approved_users if pr_author else False

print(json.dumps({
    'approval_count': approval_count,
    'approvers': approver_list,
    'sod_violation': sod_violation
}))
")

# Check for parse errors
PARSE_ERROR=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',''))")
if [[ -n "$PARSE_ERROR" ]]; then
  echo "ERROR: $PARSE_ERROR"
  exit 1
fi

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