# FastStart – Dev Environment
# Run: terraform init && terraform plan && terraform apply

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = { source = "hashicorp/random" }
  }
  backend "s3" {
    # Set via -backend-config or env; example:
    # bucket         = "faststart-terraform-state-dev"
    # key            = "terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "terraform-state-lock"
    # encrypt        = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment = var.environment
      Project      = var.project_name
      ManagedBy    = "terraform"
    }
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# VPC
module "vpc" {
  source = "../../modules/vpc"
  name_prefix = local.name_prefix
  environment = var.environment
  vpc_cidr     = var.vpc_cidr
  azs          = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# Security groups
module "security" {
  source = "../../modules/security"
  name_prefix   = local.name_prefix
  vpc_id        = module.vpc.vpc_id
  vpc_cidr      = module.vpc.vpc_cidr_block
}

# Aurora PostgreSQL + RDS Proxy
module "aurora" {
  source = "../../modules/aurora"
  name_prefix              = local.name_prefix
  environment              = var.environment
  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnet_ids
  lambda_security_group_id = module.security.lambda_sg_id
  aurora_security_group_id = module.security.aurora_sg_id
  rds_proxy_security_group_id = module.security.rds_proxy_sg_id
  instance_class           = var.aurora_instance_class
  multi_az                 = var.aurora_multi_az
  kms_key_id               = module.security.kms_key_id
}

# DynamoDB
module "dynamodb" {
  source = "../../modules/dynamodb"
  name_prefix = local.name_prefix
  environment = var.environment
  kms_key_arn = module.security.kms_key_arn
}

# S3 (intake buckets per org; policy bucket; logs)
module "s3" {
  source = "../../modules/s3"
  name_prefix  = local.name_prefix
  environment  = var.environment
  org_ids      = var.org_ids
  case_types   = var.case_types
  kms_key_arn  = module.security.kms_key_arn
}

# Lambda (API + Agents) – code from ../../../api and ../../../agents
module "lambda" {
  source = "../../modules/lambda"
  name_prefix     = local.name_prefix
  environment     = var.environment
  vpc_config      = { subnet_ids = module.vpc.private_subnet_ids, security_group_ids = [module.security.lambda_sg_id] }
  runtime         = "nodejs20.x"
  case_state_table_name = module.dynamodb.case_runtime_state_table_name
  idempotency_table_name = module.dynamodb.idempotency_keys_table_name
  event_log_table_name  = module.dynamodb.event_log_table_name
  db_proxy_endpoint = module.aurora.proxy_endpoint
  db_secret_arn    = module.aurora.secret_arn
  event_bus_name  = "default"
  bedrock_model_id = var.bedrock_model_id
  cognito_user_pool_id = var.cognito_user_pool_id != "" ? var.cognito_user_pool_id : (var.cognito_user_pool_arn != "" ? split("/", var.cognito_user_pool_arn)[1] : "")
  api_source_path = "${path.root}/../../../api"
  agents_source_path = "${path.root}/../../../agents"
}

# API Gateway
module "api_gateway" {
  source = "../../modules/api_gateway"
  name_prefix       = local.name_prefix
  environment       = var.environment
  lambda_invoke_arn  = module.lambda.api_lambda_invoke_arn
  lambda_function_name = module.lambda.api_lambda_function_name
  cognito_user_pool_arn = var.cognito_user_pool_arn
  enable_waf         = var.enable_waf
}

# EventBridge rules (CASE_INTAKE_VALIDATED -> SQS; intake_processor Lambda starts Step Functions)
module "eventbridge" {
  source = "../../modules/eventbridge"
  name_prefix         = local.name_prefix
  environment         = var.environment
  step_function_arn = module.step_functions.state_machine_arn
  data_lifecycle_lambda_arn = module.lambda.data_lifecycle_lambda_arn
}

# Step Functions
module "step_functions" {
  source = "../../modules/step_functions"
  name_prefix = local.name_prefix
  environment = var.environment
  lambda_arns = module.lambda.agent_lambda_arns
  failure_handler_arn = module.lambda.failure_handler_arn
  update_case_status_arn = module.lambda.update_case_status_arn
}

# Observability (alarms, X-Ray via Lambda/SFN, cost monitoring)
module "observability" {
  source = "../../modules/observability"
  name_prefix          = local.name_prefix
  environment          = var.environment
  api_gateway_id       = module.api_gateway.api_id
  lambda_function_names = module.lambda.all_lambda_names
  step_function_arn    = module.step_functions.state_machine_arn
  agent_lambda_names   = module.lambda.agent_lambda_names
  dlq_queue_names      = concat(
    [module.lambda.api_dlq_name, module.lambda.agents_dlq_name],
    [module.eventbridge.intake_consumer_dlq_name, module.eventbridge.eventbridge_target_dlq_name]
  )
  monthly_budget_limit = var.monthly_budget_limit
  budget_notification_emails = var.budget_notification_emails
}

# Outputs
output "api_endpoint" { value = module.api_gateway.api_endpoint }
output "db_proxy_endpoint" { value = module.aurora.proxy_endpoint }
output "case_runtime_state_table" { value = module.dynamodb.case_runtime_state_table_name }
output "idempotency_keys_table" { value = module.dynamodb.idempotency_keys_table_name }
output "step_function_arn" { value = module.step_functions.state_machine_arn }
