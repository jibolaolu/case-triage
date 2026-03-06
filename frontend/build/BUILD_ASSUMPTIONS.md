# Build Assumptions

This document records assumptions made during the conversion of the FastStart specification into an executable, production-grade system. Any missing or ambiguous spec details that were resolved for buildability are listed here.

---

## Identity & Auth

- **Cognito User Pool** is created and configured outside this repo (or via a separate Terraform workspace) with SSO IdP (e.g. Azure AD/Okta). This repo assumes the User Pool ID and App Client ID are provided via Terraform variables / Parameter Store.
- **JWT claims** for `orgId` and role are expected under `custom:orgId` and `cognito:groups` (or equivalent); token validation is done by API Gateway Cognito authorizer; Lambda reads claims from `event.requestContext.authorizer.claims`.
- **Platform Administrator** (for org creation, event replay) is assumed to be a dedicated Cognito group or a separate admin User Pool; the build uses a single pool with group "Administrators" for org-scoped admins. Cross-tenant "platform admin" can be enforced by an allow-list of user IDs or a separate role (not yet implemented).

## Networking & DNS

- **VPC** is created by Terraform with public/private subnets; NAT Gateway is used for private Lambda egress where needed. VPC endpoints (S3, DynamoDB, Bedrock, Secrets Manager, etc.) are created for private access.
- **Custom domain** for API Gateway and Amplify is optional; build uses default API Gateway URL and Amplify default URL unless `api_domain_name` / `app_domain_name` are set. ACM certificates are assumed to be created (or created by Terraform) in the same region.

## Data Stores

- **Aurora PostgreSQL** is created by Terraform; RDS Proxy is used for connection pooling. Database name, proxy endpoint, and secret ARN are passed to Lambdas via environment variables. Migrations are run manually or via a CI step (e.g. `npm run migrate`) against the target environment; Terraform does not run migrations.
- **DynamoDB** tables (case_runtime_state, idempotency_keys) are created by Terraform. Table names follow `FastStart-<env>-<table-name>`.
- **S3** buckets for intake documents are created per-organisation when an org is onboarded (via Lambda or Terraform `count`/`for_each` from a list of org IDs). Initial list of organisations is supplied via Terraform variable or Parameter Store; dynamic org creation at runtime uses `POST /api/organisations` which triggers bucket creation (Lambda + S3 API).

## AI & Bedrock

- **Bedrock model access** (e.g. Claude 3 Sonnet) is already requested and granted in the AWS account/region. Model ID is stored in Parameter Store (e.g. `/FastStart/<env>/bedrock/modelId`) and read by agent Lambdas.
- **Bedrock Agent Core** is used as described in the spec; the build scaffolds Step Functions plus Lambda agents. If Agent Core is used in its native form (Bedrock Agents API), the state machine would invoke the Bedrock Agent API instead of individual Lambdas; the current build uses Lambda-based agents for clarity and portability.
- **Textract** is invoked from Lambda via AWS SDK; sync API for small documents, async for multi-page; no separate Textract project or SNS setup beyond SDK calls.

## Events

- **EventBridge** default event bus is used; no custom bus. Event schema validation is done in producer Lambdas before `PutEvents`. Schema versions and detail types are as in `specification/EVENT_SCHEMAS.md`.
- **Event replay** reads event payload from Aurora or S3 (event log); if no event log is implemented yet, replay is limited to reconstructing from case record and re-publishing CASE_INTAKE_VALIDATED. Build includes a stub for event storage.

## Secrets & Config

- **Secrets Manager** holds DB credentials (if not using IAM auth) and any third-party API keys. Lambda execution role has permission to read secrets by ARN; secret ARNs are in Terraform variables or env vars.
- **Parameter Store** holds non-sensitive config: environment name, Bedrock model ID, feature flags, and (optional) org allow-list. Parameters under `/FastStart/<env>/`.

## Multi-Tenancy

- **Tenant context** is always derived from JWT `custom:orgId`. All APIs that are org-scoped validate that the resource’s `organisation_id` matches the token’s `orgId`; otherwise 403. No tenant in request path; tenant is implicit from identity.
- **Organisation onboarding** creates Aurora row, S3 buckets, and Cognito group. S3 bucket naming follows `<org-id>-<case-type>-applicant-intake-s3-<env>`. Case types for new orgs are supplied in the request body; a default list can be configured in Parameter Store.

## Idempotency

- **Idempotency-Key** header is required on mutation endpoints listed in the spec. Keys are stored in DynamoDB `idempotency_keys` with TTL 24 hours. Conditional put ensures one writer; duplicate request returns stored response. Request body hash is optional; if implemented, 409 on same key + different body.

## Observability

- **Structured logging** is JSON to stdout; Lambda log group is created by Terraform. No PII in logs; correlation ID (requestId/caseId) is included.
- **Metrics** are emitted via CloudWatch Embedded Metric Format (EMF) or PutMetricData; namespace `FastStart/<env>`. X-Ray is enabled on Lambda and API Gateway; sampling is 100% in production (configurable).
- **Alarms** are created for Lambda errors, API 5xx, and (optional) DLQ depth; SNS topic for alerts is created by Terraform; email subscription is manual or via variable.

## CI/CD

- **Pipeline** is GitHub Actions (or equivalent); build assumes a single workflow for deploy (dev/tst/prd) with environment-specific Terraform workspace or tfvars. Terraform state is in S3 with DynamoDB lock; backend config is in Terraform.
- **Deploy order** is: infra (Terraform) → migrations (if any) → Lambda/Step Functions deploy (Terraform or SAM/CDK). Frontend (Amplify) is separate; Amplify is connected to repo branch or built from build/ui artifact.

## Failure Handling & Recovery

- **DLQs** are attached to SQS queues that receive EventBridge or Lambda async invocations; alarm on DLQ depth > 0. Step Functions Catch routes to FailureHandler Lambda; case status set to AI_PROCESSING_FAILED; CASE_AI_FAILED event emitted.
- **Retries** follow spec: Lambda 3 retries with exponential backoff; Step Functions state retry 3 times then Catch. Idempotency and checkpointing in DynamoDB allow safe retries.

## Security

- **WAF** is attached to API Gateway and/or CloudFront if `enable_waf` is true; OWASP preset and rate rule are applied. Build includes Terraform for WAF and association.
- **IAM** roles are least-privilege; resource policies restrict S3/DynamoDB by resource ARN; no wildcard on resources where avoidable. KMS keys are used for Aurora, DynamoDB, S3, and Secrets Manager.

## What Is Not Built (Out of Scope for Initial Build)

- **Caseworker UI (Next.js)** – build contains a placeholder under `build/ui` (or reference to Amplify) and API contract; full UI implementation is a separate deliverable.
- **Citizen-facing portal** – out of scope per spec.
- **Hybrid / multi-cloud** – AWS only.
- **Real-time WebSocket** – not implemented; polling or future enhancement.
- **A/B testing for AI models** – model version is recorded; traffic splitting is not implemented.
- **Self-service tenant sign-up** – organisation creation is Admin API only; no public registration.

---

*Last updated: Build v1. All assumptions should be validated against the specification and operational requirements before production.*
