# P0 Production Controls Implementation

## Overview

This document records the implementation of production-critical P0 controls required for secure, compliant production deployment of the FastStart platform.

## Implemented P0 Controls

### 1. User Onboarding API ✅

**Implementation:**
- **Handler:** `build/api/src/handlers/inviteUser.js`
- **Route:** `POST /api/users/invite`
- **Features:**
  - Creates user in Cognito User Pool
  - Creates user record in Aurora `users` table
  - Creates invitation record in `user_invitations` table
  - Adds user to Cognito group (org-role based)
  - Validates admin role requirement
  - Enforces multi-tenant isolation (orgId validation)
  - Idempotency support
  - Audit logging

**Terraform:**
- Added Cognito permissions to Lambda IAM role
- Added `cognito_user_pool_id` variable to Lambda module
- Added `COGNITO_USER_POOL_ID` environment variable to API Lambda

**Usage:**
```json
POST /api/users/invite
Headers: Authorization, Idempotency-Key
Body: {
  "email": "user@example.com",
  "role": "Caseworker",
  "organisationId": "council-a",
  "firstName": "John",
  "lastName": "Doe"
}
```

### 2. MFA Enforcement ✅

**Implementation:**
- **Middleware:** `build/api/src/middleware/mfaCheck.js`
- **Integration:** Applied in `build/api/src/index.js` router
- **Features:**
  - Checks MFA status via Cognito AdminGetUser
  - Returns 403 if MFA not enabled
  - Skips check for public endpoints
  - Fail-closed security model

**Behavior:**
- All authenticated API requests check MFA status
- Users without MFA receive: `MFA_REQUIRED` error
- Public endpoints (e.g., `/health`) bypass MFA check
- In dev/test (no Cognito), MFA check is bypassed

**Note:** MFA setup must be enforced at Cognito User Pool level (configured separately).

### 3. Automated Data Deletion ✅

**Implementation:**
- **Lambda:** `build/agents/dataLifecycle.js`
- **Trigger:** EventBridge schedule (daily at 2 AM UTC)
- **Features:**
  - Deletes cases older than retention period (5 years default)
  - Deletes related data (documents, decisions, audit logs, etc.)
  - Deletes S3 objects for case documents
  - Processes 100 cases per run (prevents timeout)
  - Transactional deletion (rollback on error)
  - Comprehensive logging

**Terraform:**
- Lambda function: `data-lifecycle`
- EventBridge rule: `data-lifecycle-schedule` (cron: `0 2 * * ? *`)
- IAM permissions: S3 delete, Aurora delete
- Environment variable: `RETENTION_YEARS` (default: 5)

**Retention Policy:**
- Cases with status `APPROVED`, `DECLINED`, or `ARCHIVED`
- Older than 5 years from `created_at`
- Hard delete (compliance-approved)

### 4. Cost Monitoring ✅

**Implementation:**
- **AWS Budgets:** Monthly cost budget with alerts
- **Cost Anomaly Alarm:** CloudWatch alarm on EstimatedCharges
- **Features:**
  - Monthly budget limit (configurable, default: $2000)
  - Alerts at 80% and 100% of budget
  - Cost anomaly detection (20% over budget threshold)
  - SNS topic integration for notifications

**Terraform:**
- `aws_budgets_budget.monthly` (conditional on email list)
- `aws_cloudwatch_metric_alarm.cost_anomaly`
- Variables: `monthly_budget_limit`, `budget_notification_emails`

**Configuration:**
Set in `environments/dev/variables.tf` or `terraform.tfvars`:
```hcl
monthly_budget_limit = 2000
budget_notification_emails = ["admin@example.com"]
```

### 5. S3 Production Controls ✅

**Implementation:**
- **Versioning:** Enabled on all buckets
- **Lifecycle Policies:** Applied to policy and intake buckets
- **Features:**
  - Versioning enabled (rollback-safe)
  - Transition to IA after 30 days
  - Transition to Glacier after 90 days
  - Delete after retention (5 years for intake buckets)
  - Non-current version expiration (1 year)

**Terraform:**
- `aws_s3_bucket_versioning` for policy and intake buckets
- `aws_s3_bucket_lifecycle_configuration` with rules:
  - Transition to STANDARD_IA (30 days)
  - Transition to GLACIER (90 days)
  - Expiration (1825 days = 5 years for intake)
  - Non-current version expiration (365 days)

**Buckets Affected:**
- Policy bucket: `${name_prefix}-policy-definitions`
- Intake buckets: `${org-id}-${case-type}-applicant-intake-s3-${env}`

## Files Modified

### API Handlers
- `build/api/src/handlers/inviteUser.js` (NEW)
- `build/api/src/index.js` (added route + MFA check)
- `build/api/src/middleware/mfaCheck.js` (NEW)

### Agents
- `build/agents/dataLifecycle.js` (NEW)

### Infrastructure
- `build/infrastructure/terraform/modules/lambda/main.tf` (Cognito permissions, data lifecycle Lambda)
- `build/infrastructure/terraform/modules/lambda/variables.tf` (cognito_user_pool_id)
- `build/infrastructure/terraform/modules/lambda/outputs.tf` (data_lifecycle_lambda_arn)
- `build/infrastructure/terraform/modules/s3/main.tf` (versioning + lifecycle)
- `build/infrastructure/terraform/modules/eventbridge/main.tf` (data lifecycle schedule)
- `build/infrastructure/terraform/modules/eventbridge/variables.tf` (data_lifecycle_lambda_arn)
- `build/infrastructure/terraform/modules/observability/main.tf` (cost monitoring)
- `build/infrastructure/terraform/modules/observability/variables.tf` (budget variables)
- `build/infrastructure/terraform/environments/dev/main.tf` (wiring)
- `build/infrastructure/terraform/environments/dev/variables.tf` (new variables)

## Configuration Required

### Environment Variables
- `COGNITO_USER_POOL_ID` - Set in Lambda environment (extracted from ARN if needed)

### Terraform Variables
- `cognito_user_pool_id` - Cognito User Pool ID (or extracted from ARN)
- `monthly_budget_limit` - Monthly budget in USD (default: 2000)
- `budget_notification_emails` - List of email addresses for budget alerts

### Cognito Configuration (External)
- MFA must be enforced at User Pool level
- User groups must exist (e.g., `{orgId}-Caseworkers`, `{orgId}-Managers`)
- SSO configuration (if using SSO)

## Testing

### User Onboarding
```bash
curl -X POST https://api.example.com/api/users/invite \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $(uuidgen)" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "role": "Caseworker",
    "organisationId": "council-a"
  }'
```

### MFA Enforcement
- Attempt API call without MFA → Should return 403 MFA_REQUIRED
- Enable MFA in Cognito → API calls should succeed

### Data Lifecycle
- Trigger Lambda manually or wait for schedule
- Check CloudWatch logs for deletion activity
- Verify cases older than retention period are deleted

### Cost Monitoring
- Set budget limit and email addresses
- Monitor AWS Budgets console
- Verify SNS notifications on threshold breaches

### S3 Lifecycle
- Upload test object to S3 bucket
- Verify versioning is enabled
- Wait 30 days → Object transitions to IA
- Wait 90 days → Object transitions to Glacier
- Wait 5 years → Object is deleted

## Security Notes

1. **MFA Enforcement:** Fail-closed model - denies access if MFA check fails
2. **Data Deletion:** Hard delete after retention - ensure compliance approval
3. **Cost Monitoring:** Budget alerts help prevent cost overruns
4. **S3 Lifecycle:** Versioning enables rollback; lifecycle reduces costs
5. **User Onboarding:** Admin-only endpoint with org isolation

## Production Readiness

All P0 production controls are implemented and ready for deployment. Ensure:
1. Cognito User Pool is configured with MFA enforcement
2. Budget notification emails are configured
3. Retention period aligns with compliance requirements
4. S3 lifecycle policies are reviewed and approved
5. Data deletion Lambda is tested in non-production first
