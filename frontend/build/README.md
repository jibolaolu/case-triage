# FastStart Build – Execution Layer

This directory contains the **executable, production-grade** implementation of the FastStart platform, generated from the technical specification.

## Structure

```text
build/
├── BUILD_ASSUMPTIONS.md     # Assumptions made for buildability
├── README.md                # This file
├── REPOSITORY_STRUCTURE.md  # Folder map and where each concern lives
├── api/                     # API layer (Lambda + API Gateway)
│   ├── contracts/          # OpenAPI
│   ├── src/                # Lambda handlers
│   └── package.json
├── agents/                  # AI orchestration runtime (Lambdas)
│   └── package.json
├── database/               # Data layer definitions
│   └── migrations/         # Aurora PostgreSQL migrations
├── events/                 # Event contracts (JSON Schema)
│   └── schemas/
├── infrastructure/         # IaC (Terraform)
│   └── terraform/
│       ├── modules/
│       ├── environments/
│       └── ...
├── lib/                    # Shared types and constants (TypeScript)
│   ├── types/              # Case, Decision, API response types
│   └── constants/          # routes, env keys
├── shared/                 # Shared backend lib (Node.js, used by Lambdas)
│   └── nodejs/             # tenant, idempotency, observability
├── ci/                     # CI/CD (see ci/README.md)
│   └── README.md           # GitLab + AWS CodePipeline options
└── ui/                     # Caseworker UI (Next.js 14 App Router)
    ├── app/                # (auth)/login, (dashboard)/dashboard, cases, notifications, settings, admin
    ├── components/         # ui/, cases/, forms/, layout/
    ├── lib/                # api/ (client, cases, decisions), auth/, utils/
    ├── hooks/              # useCases, useCaseDetail
    ├── contexts/           # AuthContext
    ├── types/              # UI types (aligned with API)
    ├── styles/
    └── package.json
```

## Quick Start

1. **Prerequisites:** Node.js 20+, Terraform >= 1.5, AWS CLI configured, jq.
2. **Install dependencies:**
   - `cd build/api && npm ci`
   - `cd build/agents && npm ci`
   - `cd build/shared/nodejs && npm ci`
   - `cd build/ui && npm ci`
3. **Configure:** Copy `build/infrastructure/terraform/environments/dev/terraform.tfvars.example` to `terraform.tfvars` and set variables.
4. **Deploy infra:** `cd build/infrastructure/terraform/environments/dev && terraform init && terraform apply`
5. **Run migrations:** `cd build/api && npm run migrate` (after setting DB connection from Terraform outputs).
6. **Deploy Lambdas:** Terraform deploys Lambda code from `build/api` and `build/agents` (via path or S3); or use your CI pipeline.

## Specification Alignment

- **Architecture:** `../specification/ARCHITECTURE.md`
- **API rules:** `../specification/.cursor/rules/backend/api.mdc`
- **Database:** `../specification/.cursor/rules/backend/database.mdc`
- **Events:** `../specification/EVENT_SCHEMAS.md`
- **Security:** `../specification/SECURITY_COMPLIANCE.md`
- **Observability:** `../specification/OBSERVABILITY.md`
- **Failure & recovery:** `../specification/FAILURE_RECOVERY.md`

## Environment Variables (Lambda)

Set via Terraform `environment` block; values from Terraform variables or Parameter Store/Secrets Manager:

- `ENVIRONMENT` (dev|tst|prd)
- `DB_PROXY_ENDPOINT`, `DB_NAME`, `DB_SECRET_ARN` (or IAM auth)
- `CASE_RUNTIME_STATE_TABLE`, `IDEMPOTENCY_KEYS_TABLE`
- `EVENT_BUS_NAME` (default bus)
- `POWERTOOLS_SERVICE_NAME`, `LOG_LEVEL`
- `BEDROCK_MODEL_ID` (from Parameter Store in agent Lambdas)

## CI/CD

- **GitLab only:** Use `build/ci/.gitlab-ci.yml`. In GitLab set **Settings → CI/CD → CI configuration file** to `build/ci/.gitlab-ci.yml`. Stages: validate → plan → build → deploy-infra → deploy-app. Infrastructure and application deployment are separate (deploy-infra = Terraform apply; deploy-app = Lambda code update). See **ci/README.md** for variables and usage.
- **AWS CodePipeline:** Optional alternative; see **ci/README.md** and **specification/DEPLOYMENT.md**.

## Production Readiness

- Multi-tenant: orgId from JWT; all queries filtered by organisation_id.
- Secure: IAM least privilege, KMS, no PII in logs.
- Observable: Structured logs, EMF metrics, X-Ray.
- Failure-tolerant: Retries, DLQs, idempotency, Step Functions Catch.
- Auditable: Audit log table + CloudTrail.

See **BUILD_ASSUMPTIONS.md** for gaps and assumptions.
