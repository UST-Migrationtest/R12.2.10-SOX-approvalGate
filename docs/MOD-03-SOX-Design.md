# MOD-03 — SOX Approval Gate Execution
## Technical Design Document

**Document Control:**

| Field | Value |
|-------|-------|
| Module | MOD-03 |
| Version | 1.0.0 |
| Status | Approved for POC |
| Created | 2025-08-20 |
| Author | UST EBS CI/CD Team |
| Reviewer | IT Audit, DevOps Lead |
| Color Standard | UST Teal #016E75 |

---

## 1. Executive Summary

MOD-03 implements Sarbanes-Oxley (SOX) Section 404 internal controls as **live, executable enforcement mechanisms** within the GitHub Actions CI/CD pipeline for Oracle EBS R12.2.10 customization deployments.

The module answers the leadership question: *"How do we prove to auditors that no unauthorized code reaches production?"*

The answer is demonstrated through six specific behaviors:
1. The pipeline **automatically blocks** PRs with fewer than 2 approvals
2. The pipeline **automatically detects and blocks** SOD violations (author = approver)
3. PROD deployments are **visually paused** in GitHub UI until named reviewers approve
4. Every deployment generates an **immutable, machine-readable JSON audit record** retained for 7 years
5. CODEOWNERS rules **automatically enforce** Finance and IT Audit review of financial module changes
6. The deployment manifest SHA256 **proves tamper-integrity** of what was deployed

---

## 2. Regulatory Requirement Mapping

| SOX Requirement | Pipeline Control | Evidence Artifact |
|-----------------|-----------------|-------------------|
| Access control to financial systems (§302) | CODEOWNERS + branch protection | GitHub audit log + CODEOWNERS file |
| Dual authorization for financial transactions (§404) | `validate-approvals` job exits 1 if < 2 approvers | `sox_audit_log.json` → `approval_evidence.approval_actual_count` |
| Segregation of duties (§404) | SoD check in `validate_approvals.sh` | `sox_audit_log.json` → `approval_evidence.sod_check_passed` |
| Audit trail for 7 years (§802) | `retention-days: 2555` in upload-artifact step | GitHub Actions artifact: `sox-pipeline-audit-*` |
| Change management authorization (general) | PROD environment protection gate | GitHub environment deployment approval log |
| Evidence of control effectiveness (§404) | All AC-1 to AC-6 pass on every run | Green GitHub Actions badge |

---

## 3. Architecture

### 3.1 Pipeline Architecture

```
Developer pushes to feature branch
         │
         ▼
PR opened against `main`
         │
         ├─ CODEOWNERS assigns mandatory reviewers
         │   (based on paths changed)
         │
         ├─ Branch protection: requires 2 approvals
         │
         ▼
CI Pipeline: prod-deployment-sox.yml
         │
   ┌─────┴─────────────────────────────────────────┐
   │                                               │
   ▼                                               │
[Job: validate-approvals]                         │
 • Fetches PR reviews via GitHub API              │
 • Checks unique approver count >= 2             │
 • Checks PR author NOT in approvers (SoD)       │
 • EXITS 1 if violated → PIPELINE BLOCKED        │
   │                                               │
   ▼                                               │
[Job: validate-manifest]                          │
 • checks MANIFEST.txt format                     │
 • Verify all OBJECT: paths exist in repo         │
 • Compute & record SHA256 hash                   │
   │                                               │
   ▼                                               ▼
[Job: deploy-uat]                    [Job: generate-audit-record]
 • Auto-deploy to UAT EBS             (runs if: always())
 • Run smoke tests                    • Generates sox_audit_log.json
   │                                  • Uploads as artifact (2555 days)
   ▼
[Job: deploy-prod]
 • environment: PROD
 • PAUSED by GitHub Environment Protection
 • Requires 2 named humans to click APPROVE in GitHub UI
 • After approval: executes PROD deployment
 • Generates sox_audit_log.json for PROD
```

### 3.2 CODEOWNERS Control Matrix

```
Path Pattern                    Mandatory Reviewers
─────────────────────────────   ────────────────────────────────────────────
modules/payables/**             @ap-developers + @ap-finance-controllers
modules/receivables/**          @ar-developers + @ar-revenue-accountants
modules/shared/**               @senior-tech-leads + ALL module teams
.github/workflows/**            @devops-leads + @it-audit
.github/CODEOWNERS              @it-audit (only)
config/sox_config.json          @it-audit + @cfo-office (only)
scripts/generate_sox_audit*.sh  @it-audit + @devops-leads
MANIFEST.txt                    @release-managers + @it-audit
```

### 3.3 GitHub Environment Configuration

```yaml
# PROD Environment (configured in GitHub Settings → Environments)
PROD:
  required_reviewers:
    - ebs-tech-leads  # Technical sign-off
    - it-audit        # SOX compliance sign-off
  wait_timer: 5 minutes  # Mandatory reflection period
  deployment_branches:
    - main            # Only main branch can deploy to PROD
  prevent_self_review: true
```

---

## 4. SOX Audit Log Specification

### 4.1 Required Fields (AC-3)

Every `sox_audit_log.json` must contain the following fields:

```json
{
  "deployment_id":          "string — unique deployment reference",
  "deployer":               "string — GitHub username",
  "target_environment":     "enum: DEV | UAT | PROD",
  "deployment_timestamp":   "ISO 8601 UTC — e.g., 2025-08-20T10:34:17Z",
  "approvers":              ["array", "of", "reviewer", "usernames"],
  "manifest_hash":          "SHA256 hex string of MANIFEST.txt",
  "github_run_url":         "https://github.com/org/repo/actions/runs/NNNN",
  "compliance_status":      "enum: COMPLIANT | NON_COMPLIANT"
}
```

### 4.2 Retention Policy

| Field | Value |
|-------|-------|
| Retention period | 2555 days (7 years) |
| Regulatory basis | SOX §802 / PCAOB AS 3101 |
| Storage mechanism | GitHub Actions artifact upload |
| Artifact name pattern | `sox-pipeline-audit-{run_id}` |
| Backup | Azure Blob Storage: `sox-compliance-archive` container |
| Encryption | AES-256 at rest |

---

## 5. Test Scenarios

### Scenario 1 — Insufficient Approvals (AC-1)

**Setup:** Open PR with 1 approval from a reviewer who is not the PR author.

**Expected Pipeline Behavior:**

- `validate-approvals` job runs
- GitHub API returns 1 unique approver
- Script evaluates: `1 < 2` → FAIL
- Job exits with code 1
- GitHub Actions marks job as failed (red X)
- Branch protection blocks merge to `main`
- PR author sees: "Required status check 'SOX Gate 1 | PR Approval Count >= 2' did not pass"

**Evidence of Control Working:** GitHub Actions run shows red check on `validate-approvals` job.

---

### Scenario 2 — SoD Violation (AC-5)

**Setup:** PR author uses GitHub admin role to approve their own PR (or uses API to submit approval).

**Expected Pipeline Behavior:**

- `validate-approvals` job fetches approver list
- Python parser detects `pr_author in approved_users`
- Script prints: `FAIL: SOD VIOLATION — PR author 'username' is listed as an approver`
- Job exits with code 1
- Pipeline blocked regardless of approval count

**Evidence of Control Working:** Job log shows SOD VIOLATION message.

---

### Scenario 3 — Successful PROD Deployment (AC-2, AC-3, AC-4)

**Setup:** PR with 2 approvals from distinct non-author reviewers. Trigger `workflow_dispatch` with `target_env=PROD`.

**Expected Pipeline Behavior:**

1. `validate-approvals`: PASS (2 approvers, no SoD violation)
2. `validate-manifest`: PASS (MANIFEST.txt valid, hashed)
3. `deploy-uat`: PASS (UAT smoke tests green)
4. `deploy-prod`: **PAUSED** — GitHub UI shows "Waiting for review"
5. Named reviewer (+1 IT Audit member) approves in GitHub UI
6. `deploy-prod`: Runs, deploys to PROD, uploads audit log
7. `generate-audit-record`: `sox_audit_log.json` uploaded (2555-day retention)

**Evidence of Control Working:** Artifact `sox-pipeline-audit-{RUN_ID}` visible under Actions artifacts with `sox_audit_log.json` containing `compliance_status: "COMPLIANT"`.

---

### Scenario 4 — Environment Gate Visual Demo (AC-2)

**Setup:** Trigger `workflow_dispatch` targeting PROD with valid approvals.

**Expected GitHub UI Display:**

```
Actions → prod-deployment-sox.yml → Run #NNNN

Jobs:
✅ SOX Gate 1 | PR Approval Count >= 2
✅ SOX Gate 2 | Validate Deployment Manifest
✅ Deploy to UAT
⏰ Deploy to PROD (Requires Named Approvers)  ← WAITING
✅ SOX | Generate Audit Record
```

The `Deploy to PROD` job shows the reviewer waiting UI with the message:  
_"This deployment requires approval from reviewers: ebs-tech-leads, it-audit"_

---

## 6. MANIFEST.txt Specification

### Required Headers

```
DEPLOYMENT_ID: <unique ID — match CHG ticket>
CHANGE_TICKET: <ServiceNow CHG number>
JIRA_TICKET: <JIRA ticket number>
TARGET_ENV: PROD
DEPLOYMENT_DATE: YYYY-MM-DD
DEPLOYER: <github-username>
APPROVER_1: <github-username>
APPROVER_2: <github-username>
```

### Object Lines

```
OBJECT: modules/payables/plsql/XXAP_INVOICE_UTILS.pks
OBJECT: modules/payables/plsql/XXAP_INVOICE_UTILS.pkb
```

### MANIFEST.txt integrity is verified by:
1. SHA256 computed and stored in `sox_audit_log.json`
2. All `OBJECT:` paths verified to exist in the repository
3. The manifest must be approved as part of PR (CODEOWNERS: `@release-managers @it-audit`)

---

## 7. Deployment Flow — PROD

```
Developer
  │ git push feature/EBS-1234
  │ Opens PR → 2 approvals obtained
  │
Merge to main
  │
  ├─ Auto-deploy UAT (via workflow trigger on main push)
  │
  ▼
Release Manager runs workflow_dispatch:
  target_env = PROD
  deployment_id = DEP-2025-08-20-0042
  │
  ├─ validate-approvals: PASS
  ├─ validate-manifest: PASS
  ├─ deploy-uat: PASS
  │
  ▼ deploy-prod: WAITING FOR APPROVAL
  │
  IT Audit Lead clicks "Approve" in GitHub UI
  Tech Lead clicks "Approve" in GitHub UI
  │
  ▼ deploy-prod: EXECUTING
  │  • Run sqlplus scripts on EBS PROD
  │  • Run FNDLOAD for LDT files
  │  • Import OAF XMLs
  │  • Generate sox_audit_log.json
  │
  ▼ generate-audit-record: sox_audit_log.json uploaded
       retention: 2555 days
       status: COMPLIANT
```

---

## 8. Acceptance Criteria Summary

| AC | Criterion | Status |
|----|-----------|--------|
| **AC-1** | `validate-approvals` fails if < 2 distinct non-author approvers | Implemented |
| **AC-2** | PROD environment shows "Waiting for review" until named approvers sign off | Implemented (requires GitHub Environment config) |
| **AC-3** | `sox_audit_log.json` generated with all 8 required fields | Implemented |
| **AC-4** | Audit artifact retained for 2555 days | Implemented (`retention-days: 2555`) |
| **AC-5** | SoD violation detected: author in approver list → pipeline fails | Implemented |
| **AC-6** | CODEOWNERS blocks merge without Finance/Audit sign-off | Implemented (requires branch protection config) |

---

## 9. Contacts and Escalation

| Role | Team | Contact |
|------|------|---------|
| Pipeline Owner | DevOps Leads | devops@ust.com |
| SOX Control Owner | IT Audit | it-audit@ust.com |
| Financial Approver (AP) | AP Finance Controllers | ap-controllers@ust.com |
| EBS Technical Lead | EBS Dev Team | ebs-dev@ust.com |
| Release Manager | SCM Team | scm@ust.com |

---

*Document prepared by UST EBS CI/CD Framework team | UST teal color: #016E75*
