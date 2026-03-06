# Case Triage System — Gap Analysis

## How to read this document

Each gap is a missing piece between what the **frontend expects** and what the **backend/Terraform currently provides**. Each gap includes:
- **What's missing** — the gap
- **Frontend expectation** — what the UI code does or calls
- **Backend status** — what currently exists
- **Action** — a prompt describing exactly what to build

---

## GAP 1: Authentication (Cognito)

**What's missing:** There is zero authentication infrastructure. All API Gateway endpoints use `authorization = "NONE"`.

**Frontend expectation:**
- `AuthContext` has `getAccessToken()` (returns null, comment says "Replaced by Cognito when backend is wired")
- `lib/auth/session.ts` stores demo users in localStorage
- `lib/constants/env.ts` references `NEXT_PUBLIC_COGNITO_USER_POOL_ID` and `NEXT_PUBLIC_COGNITO_CLIENT_ID`
- API client (`lib/api/client.ts`) has a commented-out Bearer token interceptor
- Three roles: `ADMIN`, `CASEWORKER`, `MANAGER`

**Backend status:** No Cognito User Pool, no authorizer on API Gateway, no JWT validation.

**Action:**
> Create a new Terraform module `modules/cognito/` that provisions:
> 1. A Cognito User Pool with email sign-in, password policy, and MFA optional
> 2. A User Pool Client (for the Next.js frontend)
> 3. Three Cognito Groups: `ADMIN`, `CASEWORKER`, `MANAGER`
> 4. A Cognito User Pool Domain (for hosted UI / OAuth flows)
> 5. Output the User Pool ID, Client ID, and domain
>
> Then update `modules/api_gateway/` to:
> 1. Add a `COGNITO_USER_POOLS` authorizer referencing the Cognito User Pool
> 2. Change all methods from `authorization = "NONE"` to use the Cognito authorizer
>
> Update `modules/api_cases/` similarly for case endpoints.
>
> Pass `NEXT_PUBLIC_COGNITO_USER_POOL_ID` and `NEXT_PUBLIC_COGNITO_CLIENT_ID` as Amplify environment variables.

---

## GAP 2: GET /cases — List Cases Endpoint

**What's missing:** The frontend needs a `GET /cases` endpoint to list cases with filters. It does not exist in the backend.

**Frontend expectation:**
- `lib/api/cases.ts` calls `GET /cases?status=X&limit=N&nextToken=T`
- `hooks/useCases.ts` uses React Query to fetch case list
- Cases page shows: case ID, applicant name, type, status, priority, assigned to, updated date, AI confidence
- Currently uses `mockData.ts` with hardcoded mock cases

**Backend status:**
- `GET /cases/{caseId}/status` exists (single case status)
- `GET /cases/{caseId}/pack` exists (single case pack)
- No list-all-cases endpoint
- DynamoDB `case_runtime_state` has GSI `status-index` and `orgId-status-index` which support querying by status

**Action:**
> Create a new Lambda `get-cases` (or `list-cases`) that:
> 1. Queries DynamoDB `case_runtime_state` table (optionally filtered by status via `status-index` GSI)
> 2. Supports pagination via `limit` and `nextToken` (DynamoDB `ExclusiveStartKey`)
> 3. Returns a list of case summaries: `caseId`, `applicantName`, `status`, `priority`, `assignedTo`, `updatedAt`, `aiConfidence`, `applicationType`
> 4. Optionally joins with Aurora for richer data (applicant details, AI confidence)
>
> Add the route to `modules/api_cases/`:
> - `GET /cases` → `list-cases` Lambda
>
> Add the Lambda to `modules/lambda/` with the standard `common_env` variables.

---

## GAP 3: GET /cases/{caseId} — Full Case Detail Endpoint

**What's missing:** The frontend needs a full case detail endpoint. The existing `GET /cases/{caseId}/status` only returns status info, not the full case.

**Frontend expectation:**
- `lib/api/cases.ts` calls `GET /cases/{caseId}` for full detail
- `hooks/useCaseDetail.ts` uses React Query
- Case detail page shows: applicant info (name, NI, DOB, email, phone), documents (with view/download URLs), AI analysis (summary, recommendation, rule evaluations), audit trail, notes
- Currently uses `mockData.ts`

**Backend status:**
- `GET /cases/{caseId}/status` returns DynamoDB status + stage info only
- `GET /cases/{caseId}/pack` returns S3 case pack JSON (AI summary output)
- No endpoint returns the full case detail with applicant info, documents, AI analysis combined

**Action:**
> Create a new Lambda `get-case-detail` that:
> 1. Reads DynamoDB `case_runtime_state` for case metadata
> 2. Reads Aurora tables (`cases`, `documents`, `extracted_data`, `eval_outcomes`, `case_summaries`, `validation_results`) for rich detail
> 3. Generates presigned S3 URLs for each document
> 4. Reads `case_audit_trail` DynamoDB for audit events
> 5. Returns a combined response matching the `CaseDetail` type the frontend expects
>
> Add the route to `modules/api_cases/`:
> - `GET /cases/{caseId}` → `get-case-detail` Lambda (this resource already exists but has no GET method for full detail)

---

## GAP 4: POST /cases/{caseId}/decision — Record Decision Endpoint

**What's missing:** The frontend needs to submit caseworker decisions (approve, decline, escalate). No such endpoint exists.

**Frontend expectation:**
- `lib/api/decisions.ts` calls `POST /cases/{caseId}/decision` with body: `{ decision, justification, idempotencyKey }`
- `DecisionPanel` component triggers approve/decline/escalate with justification
- Currently simulates locally without API call

**Backend status:**
- No decision endpoint
- No Lambda for recording decisions
- Aurora has `decisions` and `escalations` tables (created by schema_init) but nothing writes to them
- DynamoDB `case_runtime_state` status could be updated to `APPROVED` / `DECLINED` / `ESCALATED`

**Action:**
> Create a new Lambda `record-decision` that:
> 1. Validates the request (decision must be approve/decline/escalate, justification required)
> 2. Checks idempotency via DynamoDB or Aurora
> 3. Writes to Aurora `decisions` table (and `escalations` if escalated)
> 4. Updates DynamoDB `case_runtime_state` status to `APPROVED`, `DECLINED`, or `ESCALATED`
> 5. Writes an audit event to `case_audit_trail` DynamoDB
> 6. Emits an EventBridge event (e.g. `CASE_DECISION_RECORDED`)
> 7. Returns the updated case status
>
> Add the route to `modules/api_cases/`:
> - `POST /cases/{caseId}/decision` → `record-decision` Lambda
>
> Create the Lambda source in `lambda_src/record_decision/`.

---

## GAP 5: Email / Notification Service

**What's missing:** The frontend has an email review page and expects emails to be sent after decisions. No email infrastructure exists.

**Frontend expectation:**
- `/email-review` page lets caseworkers review/edit AI-generated email drafts
- `EmailDraftContext` provides `subject`, `body`, `toAddress`, `toName`, `justification`, `decision`
- "Send Email & Update Case" button expects an API call
- Notifications page shows notification types: `ESCALATION_ASSIGNED`, `CASE_APPROVED`, `CASE_DECLINED`, `CASE_ASSIGNED`, `DEADLINE_APPROACHING`, `SYSTEM_ALERT`

**Backend status:** No SES, SNS for notifications, or email Lambda. No notification storage.

**Action:**
> 1. Add SES (Simple Email Service) to Terraform:
>    - Verify a sender identity (domain or email)
>    - Create an SES email template for case decisions
>
> 2. Create a Lambda `send-decision-email` that:
>    - Takes case ID, decision, email draft (subject, body, recipient)
>    - Sends via SES
>    - Logs to audit trail
>
> 3. Create a notifications system:
>    - Add a DynamoDB table `notifications` (PK: userId, SK: createdAt) or use Aurora `audit_log`
>    - Create a Lambda `get-notifications` that reads notifications for a user
>    - Add `GET /notifications` endpoint to API Gateway
>    - Create a Lambda `mark-notification-read` for `PUT /notifications/{id}/read`
>
> 4. Wire the `record-decision` Lambda to trigger `send-decision-email` (via EventBridge or direct invocation).
>
> 5. Add API Gateway routes:
>    - `POST /cases/{caseId}/email` → `send-decision-email`
>    - `GET /notifications` → `get-notifications`
>    - `PUT /notifications/{notificationId}/read` → `mark-notification-read`

---

## GAP 6: User Management API

**What's missing:** The admin user management page needs backend APIs. None exist.

**Frontend expectation:**
- `/admin/users` shows user table with name, email, role, department, status, cases assigned
- Admin can: create/invite users, change roles, deactivate/activate, delete users
- "Create New User" modal sends name, email, role, department
- Currently uses `mockUsers` from `mockData.ts`

**Backend status:**
- Aurora has `caseworkers` table (created by schema_init)
- Cognito doesn't exist yet (see GAP 1)
- No user management Lambda or API endpoint

**Action:**
> After GAP 1 (Cognito) is implemented:
>
> 1. Create Lambdas for user management:
>    - `list-users` — list Cognito users + Aurora `caseworkers` data
>    - `create-user` — create Cognito user, send invite, write to Aurora `caseworkers`
>    - `update-user-role` — update Cognito group membership + Aurora
>    - `deactivate-user` — disable Cognito user
>    - `delete-user` — delete from Cognito + soft-delete in Aurora
>
> 2. Add API Gateway routes (admin-only via Cognito group check):
>    - `GET /admin/users` → `list-users`
>    - `POST /admin/users` → `create-user`
>    - `PUT /admin/users/{userId}/role` → `update-user-role`
>    - `PUT /admin/users/{userId}/status` → `deactivate-user`
>    - `DELETE /admin/users/{userId}` → `delete-user`
>
> 3. Add Lambda-level authorization check: verify caller is in `ADMIN` Cognito group.

---

## GAP 7: Policy Management API

**What's missing:** The admin policy management page needs backend APIs. None exist.

**Frontend expectation:**
- `/admin/policies` shows policy cards with name, category, version, status, YAML content
- Admin can: view policy YAML, edit name/category, delete, upload new policy
- Currently uses hardcoded `initialPolicies` array

**Backend status:**
- Aurora has `policies`, `policy_documents`, `policy_rules`, `policy_extraction_fields`, `policy_fairness_constraints` tables
- Seed data creates sample policies
- No API endpoints for CRUD on policies

**Action:**
> Create Lambdas for policy management:
> 1. `list-policies` — read Aurora `policies` + `policy_documents`
> 2. `get-policy` — read single policy with rules and YAML content
> 3. `create-policy` — upload policy document to S3, parse and write to Aurora
> 4. `update-policy` — update policy metadata in Aurora
> 5. `delete-policy` — soft-delete policy in Aurora
>
> Add API Gateway routes (admin-only):
> - `GET /admin/policies` → `list-policies`
> - `GET /admin/policies/{policyId}` → `get-policy`
> - `POST /admin/policies` → `create-policy`
> - `PUT /admin/policies/{policyId}` → `update-policy`
> - `DELETE /admin/policies/{policyId}` → `delete-policy`

---

## GAP 8: Case Assignment

**What's missing:** Cases need to be assigned to caseworkers. No assignment mechanism exists.

**Frontend expectation:**
- Cases page shows `assignedTo` and `assignedToName` columns
- Dashboard filters cases by `assignedTo === user.id`
- Case detail shows assigned caseworker

**Backend status:**
- DynamoDB `case_runtime_state` doesn't have an `assignedTo` field in any known Lambda
- Aurora `cases` table likely has an `assigned_to` column (from schema_init)
- No assignment Lambda or auto-assignment logic

**Action:**
> 1. Add `assignedTo` to DynamoDB case items (written during intake or via a new assignment step)
> 2. Create a Lambda `assign-case` that updates DynamoDB + Aurora with the assigned caseworker
> 3. Add auto-assignment logic (round-robin or least-loaded) triggered after Step Functions completes (`CaseReadyForReview`)
> 4. Add API route: `PUT /cases/{caseId}/assign` → `assign-case`
> 5. Add a DynamoDB GSI on `assignedTo` for efficient querying by caseworker

---

## GAP 9: Settings / User Profile API

**What's missing:** The settings page needs backend persistence.

**Frontend expectation:**
- Settings page lets users update: first name, last name, phone, department
- Notification preferences: checkboxes for case assigned, ready for review, deadline, system updates
- Display theme: light/dark
- "Save Changes" button does not call any API

**Backend status:** No user profile or preferences endpoint.

**Action:**
> 1. Add `user_preferences` table to Aurora (or extend `caseworkers` table with preferences JSON)
> 2. Create Lambdas:
>    - `get-user-profile` — read Cognito user attributes + Aurora preferences
>    - `update-user-profile` — update Cognito attributes + Aurora preferences
> 3. Add API routes:
>    - `GET /users/me` → `get-user-profile`
>    - `PUT /users/me` → `update-user-profile`

---

## GAP 10: Frontend Wiring (Replace Mock Data with Real API Calls)

**What's missing:** All frontend pages use `mockData.ts`. The API client and hooks exist but are not used by pages.

**Frontend expectation:**
- `hooks/useCases.ts` and `hooks/useCaseDetail.ts` are implemented with React Query but not imported by pages
- Pages import `mockCases`, `mockUsers`, `mockNotifications` directly
- `DecisionPanel` simulates decisions locally

**Backend status:** N/A — this is a frontend change.

**Action:**
> After all backend gaps (1–9) are filled:
> 1. Wire `/cases` page to use `useCases()` hook instead of `mockCases`
> 2. Wire `/cases/[id]` page to use `useCaseDetail(id)` hook instead of `mockCases.find()`
> 3. Wire `DecisionPanel` to call `recordDecision()` from `lib/api/decisions.ts`
> 4. Wire `/email-review` to call the email API
> 5. Wire `/admin/users` to call user management APIs
> 6. Wire `/admin/policies` to call policy management APIs
> 7. Wire `/notifications` to call notifications API
> 8. Wire `/settings` to call user profile API
> 9. Wire `AuthContext` to use Cognito (amplify-js or next-auth with Cognito provider)
> 10. Remove `mockData.ts` imports

---

## GAP 11: S3 Case Pack Path Mismatch

**What's missing:** Inconsistent S3 key prefixes between the Lambda that writes case packs and the one that reads them.

**Frontend expectation:** N/A — backend-only bug.

**Backend status:**
- `case_summary` Lambda writes to `case-packs/{caseId}/case_pack.json` (hyphen)
- `get_case_pack` Lambda probes `case_packs/{caseId}/case_pack.json` (underscore) as a fallback
- The primary lookup uses `casePackS3Key` from DynamoDB which should be correct, but if that field is missing, the fallback path is wrong

**Action:**
> Standardize on one prefix (`case-packs/` with hyphen) across both Lambdas. Update `get_case_pack` fallback to use `case-packs/` instead of `case_packs/`.

---

## GAP 12: Escalation Workflow

**What's missing:** The frontend has an escalated cases page for managers, but no escalation-specific backend logic exists.

**Frontend expectation:**
- `/escalated` page (Manager role only) shows cases with status `ESCALATED`
- Managers can review and make decisions on escalated cases
- Escalation from `DecisionPanel` changes status to `ESCALATED` with a reason

**Backend status:**
- Aurora has `escalations` table but nothing writes to it
- No EventBridge event for escalation
- No notification to managers when a case is escalated

**Action:**
> 1. In the `record-decision` Lambda (GAP 4), when decision is `escalate`:
>    - Write to Aurora `escalations` table with reason
>    - Emit `CASE_ESCALATED` EventBridge event
>    - Create a notification for all users in the `MANAGER` Cognito group
> 2. Add `GET /cases?status=ESCALATED` support to the `list-cases` Lambda (GAP 2)
> 3. Add an EventBridge rule for `CASE_ESCALATED` to trigger a notification Lambda

---

## Priority Order

| Priority | Gap | Reason |
|----------|-----|--------|
| 1 | GAP 1: Cognito | Foundation — everything else depends on auth |
| 2 | GAP 2: List Cases | Core feature — case list is the main page |
| 3 | GAP 3: Case Detail | Core feature — case review is the primary workflow |
| 4 | GAP 4: Record Decision | Core feature — approve/decline/escalate is the whole point |
| 5 | GAP 8: Case Assignment | Needed for cases to appear on dashboards |
| 6 | GAP 11: S3 Path Fix | Quick bug fix |
| 7 | GAP 5: Email/Notifications | Important for workflow completeness |
| 8 | GAP 12: Escalation | Manager workflow |
| 9 | GAP 6: User Management | Admin feature |
| 10 | GAP 7: Policy Management | Admin feature |
| 11 | GAP 9: Settings/Profile | Nice to have |
| 12 | GAP 10: Frontend Wiring | Final step — connect UI to real APIs |
