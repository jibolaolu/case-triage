# FastStart – Repository Folder Structure (Build)

```
ps-faststart/
├── specification/           # Technical spec (architecture, rules, gaps)
├── requirements/            # Business requirements
├── build/                    # ⬅ EXECUTION LAYER
│   ├── BUILD_ASSUMPTIONS.md
│   ├── README.md
│   ├── REPOSITORY_STRUCTURE.md
│   ├── api/
│   │   ├── contracts/
│   │   │   └── openapi.yaml       # API contract
│   │   ├── src/
│   │   │   ├── index.js           # API Gateway router
│   │   │   └── handlers/          # applicationInit, applicationFinalize, getDecision, getCases, getCaseDetail, recordDecision
│   │   └── package.json
│   ├── agents/
│   │   ├── failureHandler.js      # Step Functions Catch
│   │   ├── updateCaseStatus.js    # MarkReadyForReview
│   │   ├── documentValidation.js
│   │   ├── dataExtraction.js
│   │   ├── policyEvaluation.js
│   │   ├── caseSummary.js
│   │   └── package.json
│   ├── database/
│   │   └── migrations/
│   │       └── 001_initial.sql     # Aurora schema
│   ├── events/
│   │   └── schemas/               # Event JSON Schema
│   │       ├── CASE_INTAKE_VALIDATED.json
│   │       └── CASE_AI_FAILED.json
│   ├── shared/
│   │   └── nodejs/                # Tenant, idempotency, observability
│   │       ├── tenant.js
│   │       ├── idempotency.js
│   │       └── observability.js
│   ├── infrastructure/
│   │   └── terraform/
│   │       ├── modules/
│   │       │   ├── vpc/
│   │       │   ├── security/     # KMS, SGs
│   │       │   ├── aurora/       # Cluster, Proxy, Secrets
│   │       │   ├── dynamodb/     # case_runtime_state, idempotency_keys
│   │       │   ├── s3/           # Policy + intake buckets
│   │       │   ├── lambda/       # API + agents + failure + update_case_status
│   │       │   ├── api_gateway/
│   │       │   ├── eventbridge/  # Rule CASE_INTAKE_VALIDATED → Step Functions
│   │       │   ├── step_functions/  # AI orchestration state machine
│   │       │   └── observability/   # SNS, CloudWatch alarms
│   │       └── environments/
│   │           └── dev/
│   │               ├── main.tf
│   │               └── variables.tf
│   ├── ci/
│   │   ├── .gitlab-ci.yml      # GitLab pipeline; set GitLab "CI configuration file" to build/ci/.gitlab-ci.yml
│   │   └── README.md           # CI usage; optional CodePipeline
│   ├── lib/                      # Shared TypeScript types and constants
│   │   ├── types/
│   │   │   └── api.ts
│   │   └── constants/
│   │       ├── routes.ts
│   │       └── env.ts
│   └── ui/                       # Next.js 14 caseworker UI
│       ├── app/
│       │   ├── (auth)/login/
│       │   ├── (dashboard)/dashboard/, cases/, cases/[id]/, notifications/, settings/, escalated/
│       │   ├── (dashboard)/admin/users/, admin/policies/
│       │   ├── layout.tsx, page.tsx, providers.tsx
│       │   └── styles/globals.css
│       ├── components/
│       │   ├── ui/               # Button
│       │   ├── cases/            # CaseCard, DecisionPanel
│       │   ├── forms/            # Input
│       │   └── layout/           # Sidebar
│       ├── lib/
│       │   ├── api/              # client, cases, decisions
│       │   ├── auth/             # session helpers (Cognito placeholder)
│       │   └── utils/            # cn
│       ├── hooks/                # useCases, useCaseDetail
│       ├── contexts/             # AuthContext
│       ├── types/                # CaseSummary, CaseDetail, Decision
│       └── package.json
```

## Terraform / IaC layout

- **Backend:** S3 + DynamoDB lock (configure in `backend.tf` or `-backend-config`).
- **Environments:** `build/infrastructure/terraform/environments/{dev,tst,prd}`.
- **Modules:** Reusable; called from environment `main.tf`.

## Service definitions

- **API:** Single Lambda (`api`) with router in `api/src/index.js`; handlers under `api/src/handlers/`.
- **Agents:** One Lambda per agent (documentValidation, dataExtraction, policyEvaluation, caseSummary) + failureHandler + updateCaseStatus; code in `build/agents/`.

## API layer

- **Contract:** `build/api/contracts/openapi.yaml`.
- **Auth:** API Gateway JWT authorizer (Cognito); orgId from `custom:orgId`.
- **Idempotency:** Required on mutations; implemented in shared `idempotency.js` and DynamoDB table.

## Event contracts

- **Location:** `build/events/schemas/*.json`.
- **Producers:** Validate payload against schema before `PutEvents`.
- **Types:** CASE_INTAKE_VALIDATED, CASE_AI_FAILED, CASE_DECISION_RECORDED, etc. (see specification/EVENT_SCHEMAS.md).

## Data schema definitions

- **Aurora:** `build/database/migrations/001_initial.sql`.
- **DynamoDB:** Tables defined in `build/infrastructure/terraform/modules/dynamodb/main.tf`.

## AI orchestration runtime

- **Step Functions:** Definition in `build/infrastructure/terraform/modules/step_functions/main.tf`.
- **Flow:** ValidateDocuments → ExtractData → EvaluatePolicy → GenerateSummary → MarkReadyForReview; Catch → HandleFailure (failureHandler).

## Security controls

- **IAM:** Lambda role with least-privilege (DynamoDB, Secrets Manager, EventBridge, S3, Bedrock, Textract).
- **KMS:** Used for Aurora, DynamoDB, S3, Secrets.
- **VPC:** Lambda in private subnets; optional VPC endpoints for AWS services.
- **WAF:** Optional on API Gateway (variable `enable_waf`).

## Observability integration

- **CloudWatch:** Lambda log groups; API Gateway access logs; alarms (Lambda errors, API 5xx).
- **SNS:** Alarm topic for alerts.
- **Structured logs:** JSON in shared `observability.js`; no PII.

## Deployment pipeline (CI/CD)

- **GitHub Actions:** `.github/workflows/deploy.yml` – Terraform init/plan/apply for dev; build API and agents artifacts.
- **Secrets:** Use AWS Secrets Manager + Parameter Store; configure in Terraform or CI secrets.

## Tenant isolation controls

- **Context:** `getOrgIdFromEvent(event)` in shared `tenant.js`.
- **Validation:** `validateOrgAccess(resourceOrgId, callerOrgId)` before any org-scoped read/write.
- **Data:** All Aurora queries filter by `organisation_id`; DynamoDB items include `org_id`.

## Recovery & retry patterns

- **Step Functions:** Retry 3x with backoff; Catch to failureHandler; case status AI_PROCESSING_FAILED; CASE_AI_FAILED event.
- **Lambda:** Default retries (3); DLQ optional per function.
- **Idempotency:** 24h TTL; conditional put; return cached response on duplicate key.

## Secrets & config management

- **DB credentials:** Secrets Manager; Lambda role has `secretsmanager:GetSecretValue`.
- **Config:** Parameter Store `/FastStart/<env>/*` (e.g. BEDROCK_MODEL_ID); set via Terraform or CLI.
