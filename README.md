# MOD-03 — SOX Approval Gate Execution

> **Module:** MOD-03 | **Program:** UST Oracle EBS CI/CD Framework  
> **Status:** POC — Demonstrates live SOX control enforcement as executable pipeline behavior  
> **Target:** GitHub Enterprise Cloud + Oracle EBS R12.2.10 (ODAA/Exadata@Azure)

## What This Repository Demonstrates

This POC implements **Sarbanes-Oxley (SOX) §404 internal controls** directly in the CI/CD pipeline:

1. **Dual Approval Gate** — PRs require 2 distinct, non-author approvals before merge to `main`
2. **Segregation of Duties (SoD)** — PR author cannot approve their own code (`validate-approvals` job)
3. **PROD Environment Protection** — GitHub Environment gate pauses for named approver sign-off before PROD deploy
4. **Immutable Audit Trail** — Every deployment generates a `sox_audit_log.json` artifact retained for **7 years (2555 days)**
5. **CODEOWNERS Enforcement** — Finance and IT Audit teams are mandatory reviewers for financial module changes
6. **Deployment Manifest Hash** — SHA256 of `MANIFEST.txt` is recorded in every audit log for tamper detection

## Quick Start — Test the SOX Controls

### Scenario 1: Trigger the Approval Gate Failure (Insufficient Approvals)

```bash
# 1. Create a branch and make a change
git checkout -b test/sox-insufficient-approvals
echo "-- test change" >> modules/payables/plsql/XXAP_INVOICE_UTILS.pks
git commit -am "test: single-approver deployment attempt"
git push origin test/sox-insufficient-approvals

# 2. Open a PR with only 1 approval
# Expected: 'SOX Gate 1 | PR Approval Count >= 2' job FAILS
# GitHub shows: "Required status check did not pass"
```

### Scenario 2: Trigger SoD Violation Detection

```bash
# Have the PR author approve their own PR
# (bypasses GitHub's own restriction using admin override — or via API)
# Expected: validate-approvals job fails with message:
#   "SOD VIOLATION — PR author 'username' is listed as an approver"
```

### Scenario 3: Successful PROD Deployment (All Gates Pass)

```bash
# 1. Open PR with 2 approvals from distinct non-author reviewers
# 2. All branch protection checks pass
# 3. Trigger manual workflow:
gh workflow run prod-deployment-sox.yml \
  -f target_env=PROD \
  -f deployment_id=DEP-2025-08-20-0042

# 4. GitHub Actions pauses at 'Deploy to PROD' — named reviewer must approve in UI
# Expected: Reviewing user approves → deploy-prod job runs → sox_audit_log.json uploaded
```

### Scenario 4: Environment Protection Gate (Visual Demo)

```
GitHub Actions UI → prod-deployment-sox.yml run
→ Job: 'Deploy to PROD (Requires Named Approvers)'
→ Status: WAITING — "Waiting for review"
→ Named approvers: [ebs-tech-leads, it-audit] must click 'Approve'
→ After approval: Deploy proceeds and audit log uploaded (2555-day retention)
```

## Repository Structure

```
ebs-sox-cicd-framework/
├── .github/
│   ├── CODEOWNERS                         # SOX SoD — who MUST review each path
│   └── workflows/
│       └── prod-deployment-sox.yml        # 6-job SOX pipeline
├── config/
│   └── sox_config.json                    # SOX control parameters (IT-Audit owned)
├── docs/
│   └── MOD-03-SOX-Design.md              # Design document with UST standards
├── modules/                               # Sample EBS objects being deployed
│   ├── payables/
│   │   └── plsql/
│   │       ├── XXAP_INVOICE_UTILS.pks
│   │       └── XXAP_INVOICE_UTILS.pkb
│   └── shared/
│       └── plsql/
│           └── XXCOM_LOGGING_PKG.pks
├── reports/
│   └── sox_audit_log_sample.json          # Pre-computed sample audit output
├── scripts/
│   ├── generate_sox_audit_log.sh          # Generates JSON audit records
│   ├── validate_approvals.sh              # PR approval and SoD validation
│   └── sox_controls_check.sh             # Pre-deploy SOX checklist
└── MANIFEST.txt                           # Deployment object manifest (SOX hashed)
```

## SOX Pipeline Architecture

```
PR Created ──► validate-approvals ──► validate-manifest ──► deploy-uat
                (2 approvals, SoD)    (MANIFEST.txt hash)    (auto)
                      │                                         │
                  FAILS HARD                              deploy-prod
                  if violated                       (BLOCKED — named reviewer
                                                     must approve in GitHub UI)
                                                             │
                                                    generate-audit-record
                                                  (sox_audit_log.json uploaded
                                                   retention: 2555 days)
```

## SOX Controls Implemented

| Control | Description | Enforcement Mechanism |
|---------|-------------|----------------------|
| **SoD-1** | Author cannot approve own PR | `validate_approvals` job + GitHub branch protection |
| **SoD-2** | 2 distinct approvers required for PROD | `validate-approvals` job (exit 1 if < 2) |
| **SoD-3** | Finance team must review AP changes | `CODEOWNERS`: `modules/payables/** = @ap-finance-controllers` |
| **SoD-4** | IT Audit owns SOX config | `CODEOWNERS`: `config/sox_config.json = @it-audit` |
| **SoD-5** | PROD deploy pauses for named sign-off | GitHub Environment Protection (PROD requires 2 reviewers) |
| **SoD-6** | Immutable audit trail per deployment | `sox_audit_log.json` artifact, 2555-day retention |
| **SoD-7** | Deployment manifest tamper detection | SHA256 of `MANIFEST.txt` in every audit log |

## GitHub Environment Configuration

You must configure the following environments in the repository settings:

**UAT Environment:**
- Required reviewers: 1 (any `ebs-tech-leads` member)
- Deployment branches: `main` only

**PROD Environment:**
- Required reviewers: 2 (must include `it-audit` team member)
- Deployment branches: `main` only
- Wait timer: 5 minutes
- Prevent self-review: enabled

```
Settings → Environments → PROD → Required Reviewers:
  - @UST-Migrationtest/ebs-tech-leads
  - @UST-Migrationtest/it-audit
```

## Branch Protection Requirements (main)

| Setting | Required Value |
|---------|---------------|
| Require PR before merge | YES |
| Required approvals | 2 |
| Require review from CODEOWNERS | YES |
| Dismiss stale reviews on push | YES |
| Require status checks | YES: validate-approvals, validate-manifest |
| Restrict push to teams | release-managers only |

## SOX Audit Log Fields (AC-4)

Every `sox_audit_log.json` must contain:

| Field | Description |
|-------|-------------|
| `deployment_id` | Unique deployment reference |
| `deployer` | GitHub username who triggered the workflow |
| `target_environment` | DEV / UAT / PROD |
| `deployment_timestamp` | ISO 8601 UTC timestamp |
| `approvers` | JSON array of reviewer usernames |
| `manifest_hash` | SHA256 of MANIFEST.txt |
| `github_run_url` | Direct link to pipeline run |
| `compliance_status` | COMPLIANT or NON_COMPLIANT |

## Pipeline Status

[![PROD Deployment — SOX Approval Gate](https://github.com/UST-Migrationtest/ebs-sox-cicd-framework/actions/workflows/prod-deployment-sox.yml/badge.svg)](https://github.com/UST-Migrationtest/ebs-sox-cicd-framework/actions/workflows/prod-deployment-sox.yml)

## Related Modules

- **MOD-01** — EBS Custom Object Deployment (the actual deploy mechanism)
- **MOD-06** — Perforce to GitHub Migration (migrates code into this framework)
