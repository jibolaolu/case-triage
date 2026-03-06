#!/bin/bash
# bulk-import.sh — run from your terraform/ directory

PREFIX="case-triage-dev"
REGION="eu-west-2"

echo "=== Importing all existing resources into Terraform state ==="

# Security Group (you hit this first)
terraform import module.aurora.aws_security_group.aurora sg-065fd28839327bd33

# Lambda Function
terraform import module.lambda.aws_lambda_function.schema_init \
  ${PREFIX}-aurora-schema-init

# CloudWatch Log Group
terraform import module.lambda.aws_cloudwatch_log_group.schema_init \
  /aws/lambda/${PREFIX}-aurora-schema-init

# Note: Aurora master password secret is created by RDS when the cluster is created (manage_master_user_password = true)

echo "=== Import complete — running plan to check drift ==="
terraform plan