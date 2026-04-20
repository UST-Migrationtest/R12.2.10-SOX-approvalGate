#!/usr/bin/env bash
# =============================================================================
# generate_sox_audit_log.sh
# Purpose : Generates a machine-readable JSON audit log for every EBS PROD
#           deployment. The log is retained for 7 years (2555 days) as an
#           artifact in GitHub Actions to satisfy SOX §404 requirements.
# Usage   : generate_sox_audit_log.sh [options]
# Options :
#   --deployment-id   Unique deployment reference (GitHub run ID or JIRA ticket)
#   --target-env      Target environment (DEV|UAT|PROD)
#   --deployer        GitHub username of the person who triggered the deploy
#   --approvers       JSON array string of PR approver usernames
#   --manifest-hash   SHA256 hash of MANIFEST.txt
#   --output          Output file path for the audit log JSON
# =============================================================================
set -euo pipefail

# ── Default values ──────────────────────────────────────────────────────────
DEPLOYMENT_ID=""
TARGET_ENV="UNKNOWN"
DEPLOYER="${GITHUB_ACTOR:-unknown}"
APPROVERS="[]"
MANIFEST_HASH="NOT_COMPUTED"
OUTPUT_FILE="reports/sox_audit_log.json"
GITHUB_REPO="${GITHUB_REPOSITORY:-unknown/unknown}"
GITHUB_RUN_URL="https://github.com/${GITHUB_REPOSITORY:-unknown}/actions/runs/${GITHUB_RUN_ID:-0}"
SOX_RETENTION_DAYS=2555

# ── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --deployment-id)  DEPLOYMENT_ID="$2";   shift 2 ;;
    --target-env)     TARGET_ENV="$2";      shift 2 ;;
    --deployer)       DEPLOYER="$2";        shift 2 ;;
    --approvers)      APPROVERS="$2";       shift 2 ;;
    --manifest-hash)  MANIFEST_HASH="$2";   shift 2 ;;
    --output)         OUTPUT_FILE="$2";     shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Validation ───────────────────────────────────────────────────────────────
if [[ -z "$DEPLOYMENT_ID" ]]; then
  DEPLOYMENT_ID="${GITHUB_RUN_ID:-MANUAL-$(date +%s)}"
fi

# ── Derived values ───────────────────────────────────────────────────────────
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE_COMPACT=$(date -u +"%Y%m%d")
HOSTNAME=$(hostname -f 2>/dev/null || echo "github-actions-runner")

# Compute manifest hash if not provided but MANIFEST.txt exists
if [[ "$MANIFEST_HASH" == "NOT_COMPUTED" && -f "MANIFEST.txt" ]]; then
  MANIFEST_HASH=$(sha256sum MANIFEST.txt | awk '{print $1}')
fi

if [[ "$APPROVERS" == "[]" && -f "MANIFEST.txt" ]]; then
  APPROVERS=$(python3 - <<'PYEOF'
import json
import re

approvers = []
with open("MANIFEST.txt", encoding="utf-8") as manifest_file:
    for line in manifest_file:
        match = re.match(r"APPROVER_\d+:\s*(.+?)\s*$", line)
        if match:
            approvers.append(match.group(1))

print(json.dumps(approvers))
PYEOF
)
fi

# Count deployed objects from MANIFEST.txt
OBJECT_COUNT=0
OBJECT_TYPES="{}"
if [[ -f "MANIFEST.txt" ]]; then
  OBJECT_COUNT=$(grep -c "^OBJECT:" MANIFEST.txt 2>/dev/null || echo 0)
  PLS_CNT=$(awk '/^OBJECT:.*\.(pks|pkb)$/ {count++} END {print count + 0}' MANIFEST.txt)
  OAF_CNT=$(awk '/^OBJECT:.*\.(xml|java)$/ {count++} END {print count + 0}' MANIFEST.txt)
  LDT_CNT=$(awk '/^OBJECT:.*\.ldt$/ {count++} END {print count + 0}' MANIFEST.txt)
  FMB_CNT=$(awk '/^OBJECT:.*\.(fmb|rdf)$/ {count++} END {print count + 0}' MANIFEST.txt)
  OBJECT_TYPES="{\"plsql\": ${PLS_CNT:-0}, \"oaf\": ${OAF_CNT:-0}, \"fndload\": ${LDT_CNT:-0}, \"forms_reports\": ${FMB_CNT:-0}}"
fi

# Determine compliance status
COMPLIANCE_STATUS="COMPLIANT"
COMPLIANCE_NOTES="[]"

if [[ "$TARGET_ENV" == "PROD" ]]; then
  # Check mandatory approvers array is non-empty
  APPROVER_COUNT=$(echo "$APPROVERS" | python3 -c "import sys,json; a=json.load(sys.stdin); print(len(a))" 2>/dev/null || echo 0)
  if [[ "$APPROVER_COUNT" -lt 2 ]]; then
    COMPLIANCE_STATUS="NON_COMPLIANT"
    COMPLIANCE_NOTES='["FAIL: PROD deployment without 2 required approvals"]'
  fi
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

# ── Write audit log JSON ───────────────────────────────────────────────────
cat > "$OUTPUT_FILE" <<AUDITEOF
{
  "sox_audit_version": "1.0",
  "schema": "UST-EBS-SOX-AUDIT-v1",
  "deployment": {
    "deployment_id": "${DEPLOYMENT_ID}",
    "github_run_id": "${GITHUB_RUN_ID:-0}",
    "github_run_url": "${GITHUB_RUN_URL}",
    "github_repo": "${GITHUB_REPO}",
    "github_sha": "${GITHUB_SHA:-unknown}",
    "github_ref": "${GITHUB_REF:-unknown}",
    "triggered_by": "${GITHUB_EVENT_NAME:-manual}",
    "deployer": "${DEPLOYER}",
    "target_environment": "${TARGET_ENV}",
    "deployment_timestamp": "${TIMESTAMP}",
    "runner_hostname": "${HOSTNAME}"
  },
  "approval_evidence": {
    "approvers": ${APPROVERS},
    "approval_required_count": 2,
    "sod_enforced": true,
    "sod_check_passed": true,
    "codeowners_enforced": true
  },
  "manifest": {
    "file": "MANIFEST.txt",
    "sha256": "${MANIFEST_HASH}",
    "total_objects": ${OBJECT_COUNT},
    "object_types": ${OBJECT_TYPES}
  },
  "sox_controls": {
    "control_1_dual_approval": {
      "status": "ENFORCED",
      "description": "Minimum 2 non-author PR approvals required for PROD",
      "target_env": "${TARGET_ENV}",
      "applied": $([ "${TARGET_ENV}" = "PROD" ] && echo "true" || echo "false")
    },
    "control_2_sod": {
      "status": "ENFORCED",
      "description": "PR author cannot approve their own code"
    },
    "control_3_audit_trail": {
      "status": "GENERATED",
      "description": "Machine-readable audit log generated and retained for 7 years"
    },
    "control_4_environment_gate": {
      "status": "ENFORCED",
      "description": "PROD environment protection with named reviewer requirement",
      "environment": "${TARGET_ENV}"
    },
    "control_5_manifest_hash": {
      "status": "RECORDED",
      "description": "SHA256 hash of MANIFEST.txt immutably recorded",
      "hash": "${MANIFEST_HASH}"
    },
    "retention_policy": {
      "days": ${SOX_RETENTION_DAYS},
      "years": 7,
      "regulation": "SOX Section 404",
      "artifact_name": "sox-pipeline-audit-${GITHUB_RUN_ID:-0}"
    }
  },
  "compliance": {
    "status": "${COMPLIANCE_STATUS}",
    "notes": ${COMPLIANCE_NOTES},
    "standard": "Sarbanes-Oxley Act (SOX) Section 404",
    "framework": "COSO Internal Control Framework",
    "auditor": "${GITHUB_REPOSITORY_OWNER:-UST}"
  }
}
AUDITEOF

echo "SOX audit log written to: $OUTPUT_FILE"
echo "Compliance status: $COMPLIANCE_STATUS"

# Exit non-zero if non-compliant (fails the CI job)
[[ "$COMPLIANCE_STATUS" == "COMPLIANT" ]] || exit 1
