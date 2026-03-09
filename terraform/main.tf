################################################################################
# Case Triage Management System — Terraform Root
# Phase 2: + Aurora Serverless v2 + Audit Trail DynamoDB + AgentCore-ready IAM
################################################################################

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "CaseTriageSystem"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  prefix     = "${var.project_name}-${var.environment}"
}

################################################################################
# MODULE: Aurora Serverless v2 — authoritative data store
# Deploy first so ARNs are available for IAM + Lambda modules
################################################################################

module "aurora" {
  source               = "./modules/aurora"
  prefix               = local.prefix
  environment          = var.environment
  region               = local.region
  account_id           = local.account_id
  lambda_exec_role_arn = module.iam.lambda_exec_role_arn
}

################################################################################
# MODULE: IAM — shared roles & policies (now includes Aurora permissions)
################################################################################

module "iam" {
  source     = "./modules/iam"
  prefix     = local.prefix
  account_id = local.account_id
  region     = local.region

  s3_bucket_arn           = module.s3.documents_bucket_arn
  dynamodb_table_arn      = module.dynamodb.table_arn
  audit_trail_table_arn   = module.dynamodb.audit_trail_table_arn
  notifications_table_arn = module.dynamodb.notifications_table_arn
  sqs_queue_arns          = module.sqs.all_queue_arns
  eventbridge_bus_arn     = module.eventbridge.bus_arn
  step_functions_arn      = module.step_functions.state_machine_arn
  cognito_user_pool_arn   = try(module.cognito.user_pool_arn, "")

  # Aurora ARNs intentionally omitted here — would create a circular dependency
  # (aurora needs iam role, iam would need aurora ARNs).
  # IAM module defaults to wildcard "*" for Aurora permissions when not provided.
  # This is acceptable for dev; for prod, add a separate iam_aurora_policy resource
  # after both modules exist.
}

################################################################################
# MODULE: S3
################################################################################

module "s3" {
  source      = "./modules/s3"
  prefix      = local.prefix
  environment = var.environment
}

################################################################################
# MODULE: DynamoDB — runtime state + audit trail
################################################################################

module "dynamodb" {
  source = "./modules/dynamodb"
  prefix = local.prefix
}

################################################################################
# MODULE: SQS
################################################################################

module "sqs" {
  source = "./modules/sqs"
  prefix = local.prefix
}

################################################################################
# MODULE: Lambda — all 6 functions + Aurora env vars
################################################################################

module "lambda" {
  source = "./modules/lambda"
  prefix = local.prefix

  lambda_exec_role_arn      = module.iam.lambda_exec_role_arn
  documents_bucket_name     = module.s3.documents_bucket_name
  documents_bucket_arn      = module.s3.documents_bucket_arn
  dynamodb_table_name       = module.dynamodb.table_name
  audit_trail_table_name    = module.dynamodb.audit_trail_table_name
  eventbridge_bus_name      = module.eventbridge.bus_name
  tech_validation_queue_arn = module.sqs.tech_validation_queue_arn
  tech_validation_queue_url = module.sqs.tech_validation_queue_url
  extraction_queue_arn      = module.sqs.extraction_queue_arn
  extraction_queue_url      = module.sqs.extraction_queue_url
  tech_validation_dlq_arn   = module.sqs.tech_validation_dlq_arn
  extraction_dlq_arn        = module.sqs.extraction_dlq_arn

  # Aurora — passed to all Lambda env vars
  aurora_cluster_arn = try(module.aurora.cluster_arn, "")
  aurora_secret_arn  = try(module.aurora.secret_arn, "")
  aurora_database    = "case_triage"

  notifications_table_name = module.dynamodb.notifications_table_name
  cognito_user_pool_id     = module.cognito.user_pool_id
  ses_sender_email         = var.ses_sender_email
  case_pack_bucket         = module.s3.documents_bucket_name

  environment = var.environment
  aws_region  = var.aws_region

  depends_on = [module.aurora]
}

################################################################################
# MODULE: API Gateway
################################################################################

module "api_gateway" {
  source = "./modules/api_gateway"
  prefix = local.prefix

  app_init_lambda_invoke_arn        = module.lambda.app_init_invoke_arn
  app_init_lambda_function_name     = module.lambda.app_init_function_name
  app_finalize_lambda_invoke_arn    = module.lambda.app_finalize_invoke_arn
  app_finalize_lambda_function_name = module.lambda.app_finalize_function_name

  cognito_user_pool_arn = module.cognito.user_pool_arn
  enable_cognito_auth   = true

  environment = var.environment
  region      = local.region
  account_id  = local.account_id
}

################################################################################
# MODULE: EventBridge
################################################################################

module "eventbridge" {
  source = "./modules/eventbridge"
  prefix = local.prefix

  step_functions_arn   = module.step_functions.state_machine_arn
  eventbridge_role_arn = module.iam.eventbridge_role_arn
  eventbridge_dlq_arn  = module.sqs.eventbridge_dlq_arn
}

################################################################################
# MODULE: Step Functions
################################################################################

module "step_functions" {
  source = "./modules/step_functions"
  prefix = local.prefix

  step_functions_role_arn      = module.iam.step_functions_role_arn
  tech_validation_queue_url    = module.sqs.tech_validation_queue_url
  extraction_queue_url         = module.sqs.extraction_queue_url
  tech_validation_lambda_arn   = module.lambda.tech_validation_arn
  data_extraction_lambda_arn   = module.lambda.data_extraction_arn
  policy_evaluation_lambda_arn = module.lambda.policy_evaluation_arn
  case_summary_lambda_arn      = module.lambda.case_summary_arn
}


# HOW TO REFERENCE FROM YOUR ROOT main.tf:

module "api_cases" {
  source                       = "./modules/api_cases"
  prefix                       = local.prefix
  region                       = local.region
  account_id                   = local.account_id
  api_gateway_id               = module.api_gateway.api_id
  api_gateway_root_resource_id = module.api_gateway.root_resource_id
  api_gateway_stage            = module.api_gateway.stage_name
  lambda_exec_role_arn         = module.iam.lambda_exec_role_arn
  dynamodb_table_name          = module.dynamodb.table_name
  case_pack_bucket             = module.s3.documents_bucket_name

  cognito_user_pool_arn = module.cognito.user_pool_arn
  enable_cognito_auth   = true

  list_cases_invoke_arn                = module.lambda.list_cases_invoke_arn
  list_cases_function_name             = module.lambda.list_cases_function_name
  get_case_detail_invoke_arn           = module.lambda.get_case_detail_invoke_arn
  get_case_detail_function_name        = module.lambda.get_case_detail_function_name
  record_decision_invoke_arn           = module.lambda.record_decision_invoke_arn
  record_decision_function_name        = module.lambda.record_decision_function_name
  assign_case_invoke_arn               = module.lambda.assign_case_invoke_arn
  assign_case_function_name            = module.lambda.assign_case_function_name
  send_email_invoke_arn                = module.lambda.send_decision_email_invoke_arn
  send_email_function_name             = module.lambda.send_decision_email_function_name
  get_notifications_invoke_arn         = module.lambda.get_notifications_invoke_arn
  get_notifications_function_name      = module.lambda.get_notifications_function_name
  mark_notification_read_invoke_arn    = module.lambda.mark_notification_read_invoke_arn
  mark_notification_read_function_name = module.lambda.mark_notification_read_function_name
  list_users_invoke_arn                = module.lambda.list_users_invoke_arn
  list_users_function_name             = module.lambda.list_users_function_name
  manage_user_invoke_arn               = module.lambda.manage_user_invoke_arn
  manage_user_function_name            = module.lambda.manage_user_function_name
  manage_policy_invoke_arn             = module.lambda.manage_policy_invoke_arn
  manage_policy_function_name          = module.lambda.manage_policy_function_name
  user_profile_invoke_arn              = module.lambda.user_profile_invoke_arn
  user_profile_function_name           = module.lambda.user_profile_function_name

  depends_on = [module.api_gateway]
}

################################################################################
# MODULE: Cognito — Authentication for Case Triage System
################################################################################

module "cognito" {
  source      = "./modules/cognito"
  prefix      = local.prefix
  environment = var.environment
  region      = local.region
}

################################################################################
# MODULE: Amplify — Next.js Caseworker Portal
# Only deployed when a GitHub access token is provided.
# Without a token, run the frontend locally: cd frontend/build/ui && npm run dev
################################################################################

module "amplify" {
  count       = var.github_access_token != "" ? 1 : 0
  source      = "./modules/amplify"
  prefix      = local.prefix
  environment = var.environment
  region      = local.region

  github_repository   = "https://github.com/jibolaolu/case-triage"
  github_branch       = "master"
  github_access_token = var.github_access_token

  api_gateway_url = module.api_gateway.base_url

  cognito_user_pool_id = module.cognito.user_pool_id
  cognito_client_id    = module.cognito.client_id
}

################################################################################
# Schema Init — invoke Lambda to create Aurora tables
# Runs after both Aurora (cluster) and Lambda (function) modules are ready.
################################################################################

resource "null_resource" "run_schema_init" {
  triggers = {
    cluster_arn = module.aurora.cluster_arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Waiting for Aurora cluster to be available..."
      for i in $(seq 1 60); do
        STATUS=$(aws rds describe-db-clusters \
          --db-cluster-identifier ${local.prefix}-postgres \
          --region ${local.region} \
          --query 'DBClusters[0].Status' --output text 2>/dev/null || echo "unknown")
        echo "  Attempt $i: status=$STATUS"
        if [ "$STATUS" = "available" ]; then break; fi
        sleep 30
      done

      echo "Waiting 60s for Serverless v2 to stabilise..."
      sleep 60

      echo "Invoking schema_init Lambda..."
      aws lambda invoke \
        --function-name ${module.lambda.schema_init_function_name} \
        --region ${local.region} \
        --payload '{}' \
        --log-type Tail \
        /tmp/schema_init_response.json

      echo "Lambda response:"
      cat /tmp/schema_init_response.json
    EOT
  }

  depends_on = [
    module.aurora,
    module.lambda,
  ]
}

# Ensures cases routes are always active after every apply
resource "null_resource" "final_stage_deploy" {
  triggers = {
    always = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOF
DEPLOYMENT_ID=$(aws apigateway create-deployment \
  --rest-api-id ${module.api_gateway.api_id} \
  --stage-name ${module.api_gateway.stage_name} \
  --region eu-west-2 \
  --query 'id' --output text)
echo "Deployed to stage with deployment: $DEPLOYMENT_ID"
EOF
  }

  depends_on = [
    module.api_gateway,
    module.api_cases
  ]
}
#end
