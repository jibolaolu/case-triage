# Case Triage Portal — API Spec vs Codebase Gap Analysis

This document maps the **23 endpoints** from the [Full API Specification](#) to what exists in the repo.

---

## Summary

| Layer | Coverage | Notes |
|-------|----------|--------|
| **Terraform (deployed API)** | **23/23** | All routes and Python Lambdas in `terraform/modules/api_cases` + `terraform/lambda_src/`. |
| **Build API (Node router)** | **23/23** | `frontend/build/api/src/index.js` + `handlers/` — all 23 routes added; supports both `/cases` and `/api/cases`. Some handlers are stubs (status, pack, notifications, admin, profile). |
| **Frontend (UI)** | **Calls all** | `lib/api/*.ts` export clients for all 23; many pages still use mock data. |

---

## Endpoint-by-endpoint

| # | Method | Spec path | Terraform / Python | Build API (Node) | Frontend client |
|---|--------|-----------|--------------------|------------------|-----------------|
| 1 | POST | `/applications/init` | ✅ `application_init` | ✅ `applicationInit.js` | — (Vite portal) |
| 2 | PUT | S3 presigned | N/A (client direct) | N/A | — |
| 3 | POST | `/applications/complete` | ✅ `application_finalize` | ✅ `applicationFinalize.js` | — (Vite portal) |
| 4 | GET | `/cases` | ✅ `list_cases` | ⚠️ Only `/api/cases` | ✅ `getCases()` → `/cases` |
| 5 | GET | `/cases/{caseId}` | ✅ `get_case_detail` | ⚠️ Only `/api/cases/:id` | ✅ `getCaseDetail()` → `/cases/:id` |
| 6 | GET | `/cases/{caseId}/status` | ✅ `get_case_status` (Python in api_cases) | ✅ `getCaseStatus.js` (stub 501) | — (Vite polling) |
| 7 | GET | `/cases/{caseId}/pack` | ✅ `get_case_pack` (Python in api_cases) | ✅ `getCasePack.js` (stub 501) | — (Vite casepack.js) |
| 8 | POST | `/cases/{caseId}/decision` | ✅ `record_decision` | ✅ `recordDecision.js` | ✅ `recordDecision()` |
| 9 | PUT | `/cases/{caseId}/assign` | ✅ `assign_case` | ✅ `assignCase.js` (Aurora) | ❌ No client (hook exists in matrix) |
| 10 | POST | `/cases/{caseId}/email` | ✅ `send_decision_email` | ✅ `sendDecisionEmail.js` (stub 200) | ✅ `sendDecisionEmail()` |
| 11 | GET | `/notifications` | ✅ `get_notifications` | ✅ `getNotifications.js` (stub empty list) | ✅ `getNotifications()` |
| 12 | PUT | `/notifications/{notificationId}/read` | ✅ `mark_notification_read` | ✅ `markNotificationRead.js` (stub) | ✅ `markNotificationRead()` |
| 13 | GET | `/admin/users` | ✅ `list_users` | ✅ `listUsers.js` (stub empty list) | ✅ `getUsers()` (mock) |
| 14 | POST | `/admin/users` | ✅ `manage_user` | ✅ `manageUser.js` (+ legacy `inviteUser` at `/api/users/invite`) | ✅ `createUser()` (mock) |
| 15 | PUT | `/admin/users/{userId}/role` | ✅ `manage_user` | ✅ `manageUser.js` | ✅ `updateUserRole()` (mock) |
| 16 | PUT | `/admin/users/{userId}/status` | ✅ `manage_user` | ✅ `manageUser.js` (body: `active` bool) | ✅ `updateUserStatus()` — align UI to `active` |
| 17 | DELETE | `/admin/users/{userId}` | ✅ `manage_user` | ✅ `manageUser.js` | ✅ `deleteUser()` (mock) |
| 18 | GET | `/admin/policies` | ✅ `manage_policy` | ✅ `managePolicy.js` (stub) | ✅ `getPolicies()` (mock) |
| 19 | GET | `/admin/policies/{policyId}` | ✅ `manage_policy` | ✅ `managePolicy.js` (stub 404) | ✅ `getPolicy()` (mock) |
| 20 | POST | `/admin/policies` | ✅ `manage_policy` | ✅ `managePolicy.js` (stub) | ✅ `createPolicy()` (mock) |
| 21 | PUT | `/admin/policies/{policyId}` | ✅ `manage_policy` | ✅ `managePolicy.js` (stub) | ✅ `updatePolicy()` (mock) |
| 22 | DELETE | `/admin/policies/{policyId}` | ✅ `manage_policy` | ✅ `managePolicy.js` (stub) | ✅ `deletePolicy()` (mock) |
| 23 | GET | `/users/me` | ✅ `user_profile` | ✅ `userProfile.js` (stub) | ✅ `getUserProfile()` (not wired) |
| 24 | PUT | `/users/me` | ✅ `user_profile` | ✅ `userProfile.js` (stub) | ✅ `updateUserProfile()` (not wired) |

**Legend:** ✅ Implemented | ⚠️ Partial / different path | ❌ Missing in that layer

---

## Path alignment: Spec vs Build API

- **Spec base URL:** `https://.../dev` → paths are **without** `/api` (e.g. `GET /cases`, `GET /cases/{caseId}`).
- **Build API router** now supports **both** `/cases` and `/api/cases` (and all spec paths), so a single Lambda can serve the full spec.
- When the **Next.js app** uses `NEXT_PUBLIC_API_URL = https://.../dev`, it calls `/cases` and `/cases/:id` (see `lib/api/cases.ts`). The **deployed** API (Terraform) exposes `/cases` and invokes **Python** Lambdas per route; the **build/api** Node router can be used as an alternative single-Lambda backend with the same paths.

---

## Implemented in Build API (Node) — all 23 routes

All spec routes are now wired in `frontend/build/api/src/index.js` and have handlers under `handlers/`:

- **Cases:** getCases, getCaseDetail, getCaseStatus (stub), getCasePack (stub), recordDecision, assignCase, sendDecisionEmail (stub).
- **Notifications:** getNotifications (stub), markNotificationRead (stub).
- **Admin users:** listUsers (stub), manageUser (create/role/status/delete stubs).
- **Admin policies:** managePolicy (list/get/create/update/delete stubs).
- **Profile:** userProfile (GET/PUT stubs).

Stubs return 200/201 with minimal or empty body, or 501 where the full implementation lives in Terraform (e.g. status, pack).

---

## Spec vs Frontend client quirks

- **PUT /admin/users/{userId}/status**: Spec request body is `{ "active": true | false }`. UI `users.ts` sends `{ status: 'ACTIVE' | 'INACTIVE' }`. Align to spec (`active` boolean) or document mapping in API.
- **POST /admin/users**: Spec has `name`, `role`, `orgId` (optional). UI `createUser` sends `name`, `email`, `role`, `department`. Add `department` to spec or map in backend.

---

## Recommended next steps

1. ~~Add missing routes and handlers~~ **Done** — all 23 routes and handlers added (some stubbed).
2. ~~Support spec paths~~ **Done** — router matches both `/cases` and `/api/cases` and all spec paths.
3. **Wire frontend** to real API for admin/users, admin/policies, notifications, users/me once handlers return real data (replace stubs with Cognito/DynamoDB/Aurora as needed).
4. **Align** frontend `updateUserStatus` body to spec: send `{ active: true | false }` (spec) instead of `{ status: 'ACTIVE' | 'INACTIVE' }` if the deployed API expects `active`.
