# Case Triage (FastStart) – Detailed App Flow Logic

This document describes the **end-to-end flow logic** of the application as derived from the codebase. It covers the UI, API, AI orchestration, and data flow.

---

## 1. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CASE TRIAGE / FASTSTART                            │
├─────────────────────────────────────────────────────────────────────────────┤
│  UI (Next.js 14)     →     API (Lambda + API Gateway)     →     Aurora PG   │
│       │                              │                                      │
│       │                              ├── EventBridge (CASE_* events)        │
│       │                              └── Step Functions (AI pipeline)       │
│       │                                       │                             │
│       │                                       ├── documentValidation       │
│       │                                       ├── dataExtraction            │
│       │                                       ├── policyEvaluation         │
│       │                                       ├── caseSummary               │
│       │                                       ├── updateCaseStatus          │
│       │                                       └── failureHandler            │
└─────────────────────────────────────────────────────────────────────────────┘
```

- **Frontend:** Next.js 14 App Router, React Query, Auth + EmailDraft contexts.
- **Backend:** Single Lambda router; handlers for cases, decisions, applications; MFA check on authenticated routes.
- **Data:** Aurora PostgreSQL (cases, decisions, documents, rules); DynamoDB (case runtime state, idempotency).
- **AI:** Step Functions state machine triggered by events; agents run as Lambdas.

---

## 2. Entry Point and Routing (UI)

| Route | Who | Behaviour |
|-------|-----|-----------|
| `/` | All | Redirects to `/login`. |
| `/login` | Unauthenticated | Login page: demo users (SSO placeholder). On login → `/dashboard`. |
| `/(dashboard)/*` | Authenticated | Sidebar layout; RBAC guards (see below). |

**Root layout** (`app/layout.tsx`): Wraps app with `Providers` (React Query, AuthProvider, EmailDraftProvider).

**Dashboard layout** (`app/(dashboard)/layout.tsx`):

- If not authenticated → redirect to `/login`.
- **RBAC:**
  - **ADMIN:** Cannot access `/cases`, `/escalated`, `/email-review`; can access `/admin/users`, `/admin/policies`.
  - **CASEWORKER / MANAGER:** Cannot access `/admin`.
  - **CASEWORKER only:** Cannot access `/escalated` (managers only).

**Navigation by role:**

- **Caseworker:** Dashboard, Case Management, Notifications, Settings.
- **Manager:** Dashboard, Case Management, Escalated Cases, Notifications, Settings.
- **Admin:** Dashboard, User Management, Policy Management, Notifications, Settings.

---

## 3. Authentication Flow

- **Session:** Stored in `localStorage` under `faststart_user` (AuthContext uses `getCurrentUser` / `setCurrentUser` from `lib/auth/session.ts`).
- **Login:** User selects a demo user on `/login` → `login(user)` updates context and localStorage → `router.push('/dashboard')`.
- **Logout:** `logout()` clears user and calls `signOut()` → clears storage and `window.location.href = '/login'`.
- **API auth:** `apiClient` (axios) interceptor attaches `Authorization: Bearer <token>` from `getAccessToken()` (Cognito key or `faststart_access_token`). Production expects JWT with `custom:orgId` for tenant isolation.

---

## 4. Case Lifecycle (End-to-End)

### 4.1 Application intake (creation)

1. **POST /applications/init** (idempotency required):
   - Validates org (from JWT) and fetches active policy.
   - Inserts row in **Aurora** `cases` with status `INTAKE_IN_PROGRESS`.
   - Generates presigned S3 upload URLs for `documents-to-upload`.
   - Writes **DynamoDB** case runtime state (e.g. `expected_upload_keys`).
   - Returns `caseId`, `uploadUrls`, `requiredDocuments`.

2. Applicant uploads documents to S3 using presigned URLs.

3. **POST /applications/complete** (application finalize):
   - Marks intake complete; triggers **EventBridge** (e.g. `CASE_INTAKE_VALIDATED`) which starts the **Step Functions** AI pipeline.

### 4.2 AI orchestration (Step Functions)

State machine: **ValidateDocuments → ExtractData → EvaluatePolicy → GenerateSummary → MarkReadyForReview**. Any failure goes to **HandleFailure**.

| Step | Lambda | Purpose |
|------|--------|--------|
| ValidateDocuments | documentValidation | Validate uploaded documents. |
| ExtractData | dataExtraction | Extract data from documents. |
| EvaluatePolicy | policyEvaluation | Evaluate policy rules. |
| GenerateSummary | caseSummary | Generate case summary / AI recommendation. |
| MarkReadyForReview | updateCaseStatus | Set case status to ready for caseworker (e.g. PENDING). |
| HandleFailure | failureHandler | On any step failure; can set status to AI_PROCESSING_FAILED and emit CASE_AI_FAILED. |

Retries: 3 with backoff; then Catch → HandleFailure.

### 4.3 Caseworker / manager review (UI)

1. **Dashboard** (`/dashboard`): Uses `useCases()` to load cases; shows stats (total, in progress, approved, escalated) and recent cases for the current user.
2. **Case list** (`/cases`): `useCases({ status })` → **GET /api/cases** (optional `status`, `page`, `limit`). Results (or mock) are filtered by search, status, priority and paginated. Each row links to `/cases/[id]`.
3. **Case detail** (`/cases/[id]`): `useCaseDetail(id)` → **GET /api/cases/:caseId**. Renders applicant info, documents (with View/Download), AI analysis, rule evaluations, notes, audit trail. If case is actionable or escalated and user is Manager, **DecisionPanel** is shown.

### 4.4 Decision flow (approve / decline / escalate)

1. User clicks Approve, Decline, or Escalate in **DecisionPanel**.
2. Modal step 1 – **Justification:** AI-suggested reason (editable); user must confirm (checkbox) and have ≥10 chars. Then “Review AI-suggested email”.
3. Modal step 2 – **Email review:** AI-generated subject/body (editable). User clicks “Send Email”.
4. **Frontend** calls `recordDecision(caseId, { decision, justification })` → **POST /api/cases/:caseId/decision** (idempotency key in headers).
5. **Backend** `recordDecision` handler:
   - Validates body (decision, justification length).
   - Gets org/user from JWT; enforces tenant (case must belong to org).
   - In a DB transaction: INSERT into `case_decisions`, UPDATE `cases.status` (APPROVED/DECLINED/ESCALATED), audit log.
   - Emits **EventBridge** `CASE_DECISION_RECORDED` and writes to event_log.
   - Returns 200 with `decisionId`, `decidedAt`; idempotency response cached.
6. UI then redirects to `/cases`.

**Escalated cases:** Only **Managers** see `/escalated`. They see cases with status ESCALATED and can open case detail and use DecisionPanel to Approve/Decline (with suggested email).

---

## 5. API Layer (Lambda router)

**Router** (`api/src/index.js`): Uses `rawPath` and HTTP method; runs MFA check for non-public paths; then dispatches:

| Path | Method | Handler |
|------|--------|---------|
| `/applications/init` | POST | applicationInit |
| `/applications/complete` | POST | applicationFinalize |
| `/applications/:id/decision` | GET | getDecision |
| `/api/cases` | GET | getCases |
| `/api/cases/:caseId` | GET | getCaseDetail |
| `/api/cases/:caseId/decision` | POST | recordDecision |
| `/api/users/invite` | POST | inviteUser |

**Shared behaviour:**

- **Tenant:** `getOrgIdFromEvent(event)`; getCases/getCaseDetail/recordDecision filter or validate by `organisation_id`.
- **Idempotency:** Required on POST init and POST decision; DynamoDB table; returns cached response when key repeated.
- **MFA:** Enforced for all authenticated routes except public paths (e.g. `/health`, `/api/public`).

**getCases:** Query Aurora `cases` by `organisation_id` and optional `status`; pagination (page, limit); returns list of case summaries.

**getCaseDetail:** Load case + case_documents, extracted_case_data, rule_evaluations; generate presigned S3 URLs for documents; audit log case access; return case detail + AI analysis.

**recordDecision:** Parse body → validate → transaction (case_decisions + update cases + audit) → EventBridge + event_log → idempotency save → response.

---

## 6. UI Data Flow (summary)

- **Cases list:** `useCases(params)` → `getCases(params)` via React Query (`queryKey: ['cases', params]`). Fallback to `mockCases` if API unavailable.
- **Case detail:** `useCaseDetail(caseId)` → `getCaseDetail(caseId)`; fallback to `getCaseById(id)` from mockData.
- **Decisions:** `DecisionPanel` → `recordDecision(caseId, body)` from `lib/api/decisions.ts` (POST); then redirect to `/cases`.
- **Auth:** `useAuth()` from AuthContext; user from localStorage; login/logout update context and storage.

---

## 7. Events and Async Behaviour

- **CASE_INTAKE_VALIDATED:** After application finalize; triggers Step Functions (AI pipeline).
- **CASE_AI_FAILED:** Emitted by failure handler when AI pipeline fails.
- **CASE_DECISION_RECORDED:** Emitted after human decision recorded; can drive notifications or downstream workflows (e.g. email sending in future).

---

## 8. File / Directory Quick Reference

| Concern | Location |
|--------|----------|
| UI entry, layout, providers | `frontend/build/ui/app/` |
| Login, dashboard, cases, escalated, admin | `frontend/build/ui/app/(auth)`, `(dashboard)/` |
| Auth context & session | `frontend/build/ui/contexts/AuthContext.tsx`, `lib/auth/session.ts` |
| API client, cases, decisions | `frontend/build/ui/lib/api/` |
| Hooks | `frontend/build/ui/hooks/useCases.ts`, `useCaseDetail.ts` |
| Decision panel (approve/decline/escalate + email) | `frontend/build/ui/components/cases/DecisionPanel.tsx` |
| API router & handlers | `frontend/build/api/src/index.js`, `handlers/` |
| AI pipeline definition | `frontend/build/infrastructure/terraform/modules/step_functions/main.tf` |
| Agent Lambdas | `frontend/build/agents/` (e.g. documentValidation, dataExtraction, policyEvaluation, caseSummary, failureHandler, updateCaseStatus) |

---

This gives the **detailed flow logic** of the app from entry, auth, and case intake through AI orchestration to caseworker/manager review and decision recording.
