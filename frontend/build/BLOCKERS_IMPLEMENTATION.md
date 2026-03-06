# BLOCKERS Implementation Summary

This document summarizes the changes made to remove the five production deployment BLOCKERs identified in the Pre-Production Readiness Review.

---

## 1. Files Created

| File | Purpose |
|------|---------|
| `build/shared/nodejs/db.js` | Aurora PostgreSQL client via RDS Proxy; `getPool()`, `query()`, `getClient()` using `DB_PROXY_ENDPOINT` and `DB_SECRET_ARN`. |
| `build/shared/nodejs/audit.js` | Audit logging to `audit_logs` table: `logDecisionRecorded`, `logStatusChanged`, `logCaseAccessed`. |

---

## 2. Files Updated

| File | Changes |
|------|----------|
| `build/infrastructure/terraform/modules/api_gateway/main.tf` | Attached Cognito JWT authorizer to both routes (`proxy` and `root`) via `authorizer_id` and `authorization_type = "JWT"` when `cognito_user_pool_arn` is set. |
| `build/shared/nodejs/package.json` | Added export `"./db": "./db.js"`. |
| `build/api/package.json` | Added dependencies: `pg`, `@aws-sdk/client-secrets-manager`, `@aws-sdk/s3-request-presigner`. |
| `build/api/src/index.js` | Import path for observability updated to `../shared/nodejs` (for bundled shared). |
| `build/api/src/handlers/applicationInit.js` | Full intake init: validate org, resolve policy, insert `cases`, put `case_runtime_state` in DynamoDB with `expected_upload_keys`, generate S3 presigned PUT URLs per document. |
| `build/api/src/handlers/applicationFinalize.js` | Load case, `validateOrgAccess(case.organisation_id, orgId)`, check status, validate S3 documents (HeadObject), insert `case_documents`, update `cases` and DynamoDB, emit `CASE_INTAKE_VALIDATED`. |
| `build/api/src/handlers/getCases.js` | Aurora query filtered by `organisation_id` and optional status; pagination. |
| `build/api/src/handlers/getCaseDetail.js` | Load case, `validateOrgAccess`, load documents/extracted_data/rule_evaluations, `logCaseAccessed`, return detail. |
| `build/api/src/handlers/getDecision.js` | Load case, `validateOrgAccess`, load `case_decisions`, return decision or PENDING. |
| `build/api/src/handlers/recordDecision.js` | Transaction: load case, `validateOrgAccess`, insert `case_decisions`, update `cases` status/decided_at, `logDecisionRecorded`, `logStatusChanged`. |
| `build/ci/.gitlab-ci.yml` | Build API zip: copy `shared/nodejs` into `api/shared`, include `shared` in zip. |

---

## 3. Database Queries Added

- **applicationInit:** `SELECT 1 FROM organisations`, `SELECT policy_id FROM policies WHERE organisation_id AND case_type_id AND status`, `INSERT INTO cases`.
- **applicationFinalize:** `SELECT case FROM cases`, `INSERT INTO case_documents` (per validated doc), `UPDATE cases SET status, intake_completed_at`.
- **getCases:** `SELECT COUNT(*) FROM cases WHERE organisation_id AND (status)`, `SELECT ... FROM cases WHERE organisation_id AND (status) ORDER BY updated_at LIMIT/OFFSET`.
- **getCaseDetail:** `SELECT case FROM cases`, `SELECT FROM case_documents`, `SELECT FROM extracted_case_data`, `SELECT FROM rule_evaluations`, `INSERT INTO audit_logs` (CASE_ACCESSED).
- **getDecision:** `SELECT case FROM cases`, `SELECT FROM case_decisions`.
- **recordDecision:** `SELECT case FROM cases FOR UPDATE`, `INSERT INTO case_decisions`, `UPDATE cases SET status, decided_at`, `INSERT INTO audit_logs` (DECISION_RECORDED, STATUS_CHANGED).

---

## 4. Security Controls Enforced

- **API authentication:** When `cognito_user_pool_arn` is set in Terraform, all routes (ANY / and ANY /{proxy+}) require the Cognito JWT authorizer; no endpoint is publicly callable without a valid token.
- **Tenant enforcement:** Every org-scoped handler loads the resource from Aurora, then calls `validateOrgAccess(resource.organisation_id, callerOrgId)`; mismatches throw `TenantContextError` (403).
- **Audit:** Decision recording and status changes write to `audit_logs`; case detail view logs CASE_ACCESSED.

---

## 5. Tenant Isolation Guarantees

- **getCases:** Results filtered by `organisation_id = getOrgIdFromEvent(event)`; no cross-tenant data.
- **getCaseDetail:** Case loaded by ID; 403 if `case.organisation_id !== callerOrgId`.
- **getDecision:** Same as getCaseDetail.
- **recordDecision:** Case loaded and locked; 403 if org mismatch before any write.
- **applicationFinalize:** Case loaded; 403 if `case.organisation_id !== callerOrgId`; then S3/DynamoDB/Aurora updates only for that case.
- **applicationInit:** Org validated (must exist and be active); case and state created for that org only.

---

## Deployment Note

- **Cognito:** Set `cognito_user_pool_arn` in Terraform (e.g. in `terraform.tfvars` or CI) so the API Gateway authorizer is created and attached; otherwise routes remain unauthenticated.
- **API zip:** The GitLab CI build copies `build/shared/nodejs` into `build/api/shared` before zipping so Lambda has access to `shared/nodejs` (db, audit, tenant, idempotency, observability).
