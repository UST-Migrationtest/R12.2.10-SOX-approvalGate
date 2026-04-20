# CLAUDE.md — MOD-03: SOX Approval Gate Execution

> **Read this file before any task in this repository.**  
> It provides all context an AI assistant needs to work effectively on this module.

---

## 1. Project Identity *(Reduces Repetitive Explanations)*

### What This Module Is
- **Module ID:** MOD-03 — SOX Approval Gate Execution  
- **Program:** UST Oracle EBS CI/CD Modernization Framework  
- **Goal:** Implement SOX §404 internal controls as live, executable GitHub Actions pipeline behavior — not documentation, but actual enforcement  
- **Environment:** GitHub Enterprise Cloud, Oracle EBS R12.2.10 on ODAA (Exadata@Azure)  
- **Key Principle:** Every control must BLOCK the pipeline if violated. Warnings are not sufficient.

### What This Module Demonstrates (POC Scope)
1. PR rejection when fewer than 2 approvals
2. SoD violation detection (author cannot approve own PR)
3. PROD environment gate — named approver must click Approve in GitHub UI
4. Machine-readable `sox_audit_log.json` artifact with 7-year retention
5. CODEOWNERS enforcing Finance/Audit review for financial module changes

### Tech Stack
- **GitHub Actions** — Primary enforcement mechanism
- **GitHub Environment Protection** — PROD gate with named reviewer requirement
- **GitHub CODEOWNERS** — Mandatory reviewer rules per financial domain
- **Bash scripts** — `generate_sox_audit_log.sh`, `validate_approvals.sh`, `sox_controls_check.sh`
- **Python 3.8+** — Approval parsing within validate_approvals.sh
- **GitHub API** — PR review retrieval (`gh api repos/.../pulls/.../reviews`)

---

## 2. Terminology *(Avoids Misunderstandings)*

| Term | Meaning | Do NOT confuse with |
|------|---------|---------------------|
| **SoD** | Segregation of Duties — developer cannot approve their own code | SOX (the regulation) |
| **SOX §404** | Sarbanes-Oxley Act Section 404 — requires internal controls over financial reporting | SOC 2 (different framework) |
| **Environment Protection** | GitHub repo setting that pauses a workflow job for named human approval | Branch protection (different; applies to merges) |
| **PR Approval** | GitHub "Approved" review state (not just a comment) | "LGTM" comment without formal review |
| **CODEOWNERS** | File at `.github/CODEOWNERS` that designates mandatory PR reviewers per path | PR reviewers tab (manual, not enforced) |
| **Dual Approval** | 2 distinct non-author approvers required (SOX control) | 2 approvals from any person including author |
| **Audit Artifact** | `sox_audit_log.json` uploaded to GitHub Actions with 2555-day retention | Audit log in a database (not sufficient for SOX) |
| **Manifest Hash** | SHA256 of `MANIFEST.txt` — proves WHAT was deployed was WHAT was approved | Git SHA (proves WHEN code changed) |
| **COMPLIANT** | `compliance.status` field in audit log = "COMPLIANT" | Test passed (different — COMPLIANT requires all controls) |

### SOX Pipeline Job Names (exact names matter for status checks)

| Job Key | Display Name | Purpose |
|---------|-------------|---------|
| `validate-approvals` | `SOX Gate 1 \| PR Approval Count >= 2` | Blocks if < 2 non-author approvals |
| `validate-manifest` | `SOX Gate 2 \| Validate Deployment Manifest` | Validates MANIFEST.txt format and hashes |
| `deploy-uat` | `Deploy to UAT` | Auto-deploys to UAT after gates pass |
| `deploy-prod` | `Deploy to PROD (Requires Named Approvers)` | **Paused** by GitHub Environment Protection |
| `generate-audit-record` | `SOX \| Generate Audit Record` | Runs `always()` — audit even if deployment fails |

---

## 3. File Map *(Faster File Context Loading)*

### Critical Files — Read These First

| File | Purpose | Owner (CODEOWNERS) |
|------|---------|-------------------|
| `.github/workflows/prod-deployment-sox.yml` | Master SOX pipeline | DevOps Leads + IT Audit |
| `.github/CODEOWNERS` | Mandatory reviewer rules | IT Audit (only they can change it) |
| `config/sox_config.json` | SOX control parameters (min approvers, thresholds, retention) | IT Audit + CFO Office |
| `scripts/generate_sox_audit_log.sh` | JSON audit log generator | IT Audit + DevOps Leads |
| `scripts/validate_approvals.sh` | PR approval and SoD validation | IT Audit + DevOps Leads |
| `scripts/sox_controls_check.sh` | Pre-deployment control checklist | IT Audit |
| `MANIFEST.txt` | Lists all objects in each deployment | Release Managers + IT Audit |
| `reports/sox_audit_log_sample.json` | Reference audit log structure | IT Audit |

### Supporting Files

| File | Purpose |
|------|---------|
| `modules/payables/plsql/XXAP_INVOICE_UTILS.pks/pkb` | Sample EBS object being deployed |
| `modules/shared/plsql/XXCOM_LOGGING_PKG.pks` | Sample shared utility |

---

## 4. Code Review Standards *(Reduces Code Review Back-and-Forth)*

### GitHub Actions Workflows
- SOX pipeline job names MUST match the status check names in `config/sox_config.json`
- `generate-audit-record` MUST have `if: always()` — it cannot be skipped on failure
- `deploy-prod` MUST reference `environment: PROD` to trigger GitHub Environment Protection
- Artifact retention MUST be `${{ env.SOX_AUDIT_RETENTION_DAYS }}` (2555 — defined once, used consistently)

### Audit Log Script (`generate_sox_audit_log.sh`)
- Must produce valid JSON (`python3 -m json.tool <output>` must succeed)
- Must include ALL 8 fields listed in `sox_config.json`.`audit_trail.required_fields`
- Must return exit code 1 if `compliance_status` is "NON_COMPLIANT"
- MUST write audit log even if approval count is insufficient (fail-after-write, not fail-before-write)

### CODEOWNERS
- Owner path patterns must be in order from most-specific to least-specific (bottom wins in GitHub)
- Team names must be formatted as `@org/team-name` (not `@username`)
- `config/sox_config.json` must ALWAYS require `@it-audit` as owner

### MANIFEST.txt
- Required headers: `DEPLOYMENT_ID`, `TARGET_ENV`, `DEPLOYER`, `DEPLOYMENT_DATE`, `CHANGE_TICKET`
- Object lines must start with `OBJECT:` (exact keyword)
- One object per line — no globs, no directories

---

## 5. Search Patterns *(Prevents Redundant Searches)*

| "I need to find..." | Look here |
|--------------------|-----------|
| How SOX approval count is validated | `scripts/validate_approvals.sh` |
| What SOX controls the pipeline enforces | `.github/workflows/prod-deployment-sox.yml` (job names starting with "SOX") |
| The JSON structure of audit logs | `reports/sox_audit_log_sample.json` |
| Who owns which files (mandatory reviewers) | `.github/CODEOWNERS` |
| SOX control parameters (threshold, retention) | `config/sox_config.json` |
| How PROD environment gate works | `prod-deployment-sox.yml` → `deploy-prod` job → `environment: PROD` |
| Audit log generation logic | `scripts/generate_sox_audit_log.sh` |
| Pre-deployment checklist | `scripts/sox_controls_check.sh` |
| Sample deployment manifest format | `MANIFEST.txt` |
| EBS packages being deployed | `modules/payables/plsql/`, `modules/shared/plsql/` |

---

## 6. Success Criteria *(Goal-Driven Execution)*

**This POC is COMPLETE when ALL of the following can be demonstrated:**

| # | Acceptance Criterion | How to Verify |
|---|---------------------|---------------|
| **AC-1** | PR with 1 approval → `validate-approvals` job fails | Open PR with 1 approval; confirm red check in GitHub UI |
| **AC-2** | PROD environment gate shows "Waiting for review" | Trigger `workflow_dispatch` with `target_env=PROD`; confirm pause |
| **AC-3** | Successful deploy generates `sox_audit_log.json` with all required fields | Check Actions artifacts; validate JSON with `python3 -m json.tool` |
| **AC-4** | Audit artifact retention = 2555 days | Inspect artifact details in GitHub Actions UI |
| **AC-5** | SoD violation detected when author is approver | Use repo admin override to self-approve; confirm FAIL message |
| **AC-6** | CODEOWNERS blocks merge without Finance/Audit sign-off | Attempt to merge AP change without `@ap-finance-controllers` |

**Loop until verified:** Run `scripts/sox_controls_check.sh` against the configured repo. ALL checks must return PASS before POC is considered done.

---

## 7. Touch Rules *(Surgical Changes)*

### Change Freely
- `modules/payables/` and `modules/shared/` — sample EBS deployment objects (test data)
- `README.md` — documentation

### Change with Careful Review (requires 2 approvals including IT Audit)
- `.github/workflows/prod-deployment-sox.yml` — any change here affects ALL deployments
- `scripts/validate_approvals.sh` — a bug here can create false-positive approval counts
- `scripts/generate_sox_audit_log.sh` — a bug here creates incomplete audit records

### Do NOT Touch Without IT Audit Approval
- `.github/CODEOWNERS` — owned exclusively by IT Audit team
- `config/sox_config.json` — SOX control parameters; changes affect compliance posture
- The `2555` retention day constant (7 years — SOX mandates this)
- The `2` minimum approver count (SOX §404 dual-control requirement)

---

## 8. Simplicity First *(Solution Constraints)*

### Minimum Viable for This POC
- 2 PR approvals enforced at pipeline level (not just at branch protection level)
- PROD environment gate via GitHub Environment Protection
- `sox_audit_log.json` with 8 required fields, 2555-day retention
- CODEOWNERS with at least AP and shared module coverage

### What to NOT Build
- ❌ No custom GitHub App — use standard GitHub Actions + GitHub API
- ❌ No database audit store — GitHub Actions artifacts satisfy this POC
- ❌ No PagerDuty or SIEM integration (that's operational; config stubs provided)
- ❌ No real EBS deployment scripts (the `simulate` shell commands are sufficient for POC)
- ❌ No token management beyond `GITHUB_TOKEN` (no external vault integration in POC)

---

## 9. Decision Log *(Think Before Coding)*

| Decision | Rationale | Alternative Considered |
|----------|-----------|------------------------|
| **2 approvals enforced in pipeline, not just branch protection** | Branch protection can be bypassed by admins; pipeline job fails the run regardless | Branch protection only (bypassable with admin role) |
| **`generate-audit-record` runs `if: always()`** | SOX requires audit even for failed deployments — failure must be auditable | Only generate on success (incomplete audit trail) |
| **Environment Protection for PROD gate** | Native GitHub feature — no custom code; directly visible to auditors | Custom approval bot (more complex, harder to audit) |
| **SHA256 of MANIFEST.txt in audit log** | Proves what was deployed matches what was approved; tamper-detectable | Git SHA only (doesn't prove what's in the manifest) |
| **2555-day retention (7 years)** | SOX §802 requires 7-year record retention for financial controls evidence | 90 days (GitHub default — non-compliant for SOX) |
| **CODEOWNERS with team slugs, not individuals** | Teams persist; individuals leave the company | Individual usernames (brittle; breaks when person leaves) |
| **`compliance_status` COMPLIANT/NON_COMPLIANT in audit log** | Auditors need a binary field for automated compliance reporting | Narrative text only (harder to parse at scale) |

### Known Edge Cases
- **GitHub admin bypass:** Admins can bypass branch protection. The `validate-approvals` pipeline job provides an additional code-level check. Alert: even pipeline jobs can be re-run by admins — for full SOX assurance, integrate with an external SIEM (out of scope for this POC).
- **Forked repo PRs:** GitHub does not allow `GITHUB_TOKEN` to access PR review status on forks. The `validate_approvals.sh` script assumes a non-fork PR. Document this limitation.
- **Clock skew:** Audit log timestamps use `date -u` (UTC). Ensure runner timezone is UTC to avoid time offset issues.
