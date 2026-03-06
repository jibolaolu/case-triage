# FastStart – Terraform Infrastructure

AWS infrastructure for FastStart: VPC, Aurora, DynamoDB, S3, Lambda, API Gateway, EventBridge, Step Functions, Cognito (optional), observability, security.

## Layout

- **modules/** – Reusable Terraform modules (vpc, aurora, dynamodb, lambda, api-gateway, eventbridge, step-functions, security, observability)
- **environments/dev|tst|prd/** – Environment-specific `main.tf`, `variables.tf`, `terraform.tfvars`, backend config
- **shared/** – Backend (S3 + DynamoDB lock), provider versions

## Backend

State is stored in S3 with DynamoDB lock. Configure in `backend.tf` per environment:

```hcl
terraform {
  backend "s3" {
    bucket         = "faststart-terraform-state-<env>"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

## Apply Order

1. Bootstrap: create S3 bucket and DynamoDB table for state (one-time).
2. `terraform init` and `terraform apply` in the target environment directory.
3. Run DB migrations after Aurora is created (see build/api).
4. Deploy Lambda code: Terraform references local path or S3 zip; update code and re-apply or use CI.

## Variables (Key)

- `environment` – dev | tst | prd
- `project_name` – FastStart
- `region` – AWS region
- `org_ids` – List of organisation IDs for initial S3 bucket creation (optional; can be created via API)
- `cognito_user_pool_id`, `cognito_client_id` – From existing Cognito or created by module
- `enable_waf` – Boolean for WAF on API Gateway
- `aurora_instance_class`, `aurora_multi_az` – DB sizing

See `environments/dev/variables.tf` for full list.
