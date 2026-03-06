################################################################################
# modules/lambda/main.tf  (UPDATED)
#
# CHANGES:
#   + aurora_cluster_arn / aurora_secret_arn / aurora_database variables
#   + audit_trail_table_name variable
#   + All 6 agent functions receive AURORA_* + AUDIT_TRAIL_TABLE env vars
#   + schema_init Lambda added here (avoids circular dep with aurora module)
#   + BEDROCK_MODEL_ID env var on extraction, policy, summary functions
################################################################################

variable "prefix"                    {}
variable "lambda_exec_role_arn"      {}
variable "documents_bucket_name"     {}
variable "documents_bucket_arn"      {}
variable "dynamodb_table_name"       {}
variable "audit_trail_table_name"    {}
variable "eventbridge_bus_name"      {}
variable "tech_validation_queue_arn" {}
variable "tech_validation_queue_url" {}
variable "extraction_queue_arn"      {}
variable "extraction_queue_url"      {}
variable "tech_validation_dlq_arn"   {}
variable "extraction_dlq_arn"        {}
variable "environment"               {}
variable "aws_region"                {}
# Aurora — populated after aurora module creates the cluster
variable "aurora_cluster_arn"        { default = "" }
variable "aurora_secret_arn"         { default = "" }
variable "aurora_database"           { default = "case_triage" }
variable "notifications_table_name"  { default = "" }
variable "cognito_user_pool_id"      { default = "" }
variable "ses_sender_email"          { default = "noreply@example.com" }
variable "case_pack_bucket"          { default = "" }

locals {
  runtime    = "python3.12"
  source_dir = "${path.module}/../../lambda_src"

  # Env vars shared by all 6 agent Lambdas
  common_env = {
    DOCUMENTS_BUCKET   = var.documents_bucket_name
    DYNAMODB_TABLE     = var.dynamodb_table_name
    AUDIT_TRAIL_TABLE  = var.audit_trail_table_name  # NEW
    EVENTBRIDGE_BUS    = var.eventbridge_bus_name
    ENVIRONMENT        = var.environment
    AWS_ACCOUNT_REGION = var.aws_region
    PRESIGNED_URL_TTL  = "900"
    AURORA_CLUSTER_ARN = var.aurora_cluster_arn       # NEW
    AURORA_SECRET_ARN  = var.aurora_secret_arn         # NEW
    AURORA_DATABASE    = var.aurora_database            # NEW
  }
}

# ─── Zip packages ─────────────────────────────────────────────────────────────

data "archive_file" "app_init" {
  type        = "zip"
  source_dir  = "${local.source_dir}/application_init"
  output_path = "/tmp/app_init.zip"
}

data "archive_file" "app_finalize" {
  type        = "zip"
  source_dir  = "${local.source_dir}/application_finalize"
  output_path = "/tmp/app_finalize.zip"
}

data "archive_file" "tech_validation" {
  type        = "zip"
  source_dir  = "${local.source_dir}/tech_validation"
  output_path = "/tmp/tech_validation.zip"
}

data "archive_file" "data_extraction" {
  type        = "zip"
  source_dir  = "${local.source_dir}/data_extraction"
  output_path = "/tmp/data_extraction.zip"
}

data "archive_file" "policy_evaluation" {
  type        = "zip"
  source_dir  = "${local.source_dir}/policy_evaluation"
  output_path = "/tmp/policy_evaluation.zip"
}

data "archive_file" "case_summary" {
  type        = "zip"
  source_dir  = "${local.source_dir}/case_summary"
  output_path = "/tmp/case_summary.zip"
}

data "archive_file" "schema_init" {
  type        = "zip"
  source_dir  = "${local.source_dir}/schema_init"
  output_path = "/tmp/schema_init.zip"
}

data "archive_file" "list_cases" {
  type        = "zip"
  source_dir  = "${local.source_dir}/list_cases"
  output_path = "/tmp/list_cases.zip"
}

data "archive_file" "get_case_detail" {
  type        = "zip"
  source_dir  = "${local.source_dir}/get_case_detail"
  output_path = "/tmp/get_case_detail.zip"
}

data "archive_file" "record_decision" {
  type        = "zip"
  source_dir  = "${local.source_dir}/record_decision"
  output_path = "/tmp/record_decision.zip"
}

data "archive_file" "assign_case" {
  type        = "zip"
  source_dir  = "${local.source_dir}/assign_case"
  output_path = "/tmp/assign_case.zip"
}

data "archive_file" "send_decision_email" {
  type        = "zip"
  source_dir  = "${local.source_dir}/send_decision_email"
  output_path = "/tmp/send_decision_email.zip"
}

data "archive_file" "get_notifications" {
  type        = "zip"
  source_dir  = "${local.source_dir}/get_notifications"
  output_path = "/tmp/get_notifications.zip"
}

data "archive_file" "mark_notification_read" {
  type        = "zip"
  source_dir  = "${local.source_dir}/mark_notification_read"
  output_path = "/tmp/mark_notification_read.zip"
}

data "archive_file" "list_users" {
  type        = "zip"
  source_dir  = "${local.source_dir}/list_users"
  output_path = "/tmp/list_users.zip"
}

data "archive_file" "manage_user" {
  type        = "zip"
  source_dir  = "${local.source_dir}/manage_user"
  output_path = "/tmp/manage_user.zip"
}

data "archive_file" "manage_policy" {
  type        = "zip"
  source_dir  = "${local.source_dir}/manage_policy"
  output_path = "/tmp/manage_policy.zip"
}

data "archive_file" "user_profile" {
  type        = "zip"
  source_dir  = "${local.source_dir}/user_profile"
  output_path = "/tmp/user_profile.zip"
}

# ─── Lambda: ApplicationInit ──────────────────────────────────────────────────

resource "aws_lambda_function" "app_init" {
  function_name    = "${var.prefix}-application-init"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 300
  memory_size      = 256
  filename         = data.archive_file.app_init.output_path
  source_code_hash = data.archive_file.app_init.output_base64sha256

  environment { variables = local.common_env }
  tracing_config { mode = "Active" }
  tags = { Function = "application-init" }
}

resource "aws_cloudwatch_log_group" "app_init" {
  name              = "/aws/lambda/${aws_lambda_function.app_init.function_name}"
  retention_in_days = 30
}

# ─── Lambda: ApplicationFinalize ──────────────────────────────────────────────

resource "aws_lambda_function" "app_finalize" {
  function_name    = "${var.prefix}-application-finalize"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.app_finalize.output_path
  source_code_hash = data.archive_file.app_finalize.output_base64sha256

  environment { variables = local.common_env }
  tracing_config { mode = "Active" }
  tags = { Function = "application-finalize" }
}

resource "aws_cloudwatch_log_group" "app_finalize" {
  name              = "/aws/lambda/${aws_lambda_function.app_finalize.function_name}"
  retention_in_days = 30
}

# ─── Lambda: Agent 1 — TechValidation ────────────────────────────────────────

resource "aws_lambda_function" "tech_validation" {
  function_name    = "${var.prefix}-tech-validation"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 300
  memory_size      = 512
  filename         = data.archive_file.tech_validation.output_path
  source_code_hash = data.archive_file.tech_validation.output_base64sha256

  environment {
    variables = merge(local.common_env, {
      TECH_VALIDATION_QUEUE_URL = var.tech_validation_queue_url
    })
  }
  tracing_config { mode = "Active" }
  tags = { Function = "tech-validation" }
}

resource "aws_lambda_event_source_mapping" "tech_validation_sqs" {
  event_source_arn                   = var.tech_validation_queue_arn
  function_name                      = aws_lambda_function.tech_validation.arn
  batch_size                         = 1
  maximum_batching_window_in_seconds = 0
  function_response_types            = ["ReportBatchItemFailures"]
}

resource "aws_cloudwatch_log_group" "tech_validation" {
  name              = "/aws/lambda/${aws_lambda_function.tech_validation.function_name}"
  retention_in_days = 30
}

# ─── Lambda: Agent 2 — DataExtraction ────────────────────────────────────────

resource "aws_lambda_function" "data_extraction" {
  function_name    = "${var.prefix}-data-extraction"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 300
  memory_size      = 1024
  filename         = data.archive_file.data_extraction.output_path
  source_code_hash = data.archive_file.data_extraction.output_base64sha256

  environment {
    variables = merge(local.common_env, {
      EXTRACTION_QUEUE_URL = var.extraction_queue_url
      BEDROCK_MODEL_ID     = "anthropic.claude-3-7-sonnet-20250219-v1:0"
    })
  }
  tracing_config { mode = "Active" }
  tags = { Function = "data-extraction" }
}

resource "aws_lambda_event_source_mapping" "data_extraction_sqs" {
  event_source_arn                   = var.extraction_queue_arn
  function_name                      = aws_lambda_function.data_extraction.arn
  batch_size                         = 1
  maximum_batching_window_in_seconds = 0
  function_response_types            = ["ReportBatchItemFailures"]
}

resource "aws_cloudwatch_log_group" "data_extraction" {
  name              = "/aws/lambda/${aws_lambda_function.data_extraction.function_name}"
  retention_in_days = 30
}

# ─── Lambda: Agent 3 — PolicyEvaluation ──────────────────────────────────────

resource "aws_lambda_function" "policy_evaluation" {
  function_name    = "${var.prefix}-policy-evaluation"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 120
  memory_size      = 512
  filename         = data.archive_file.policy_evaluation.output_path
  source_code_hash = data.archive_file.policy_evaluation.output_base64sha256

  environment {
    variables = merge(local.common_env, {
      BEDROCK_MODEL_ID = "anthropic.claude-3-7-sonnet-20250219-v1:0"
    })
  }
  tracing_config { mode = "Active" }
  tags = { Function = "policy-evaluation" }
}

resource "aws_cloudwatch_log_group" "policy_evaluation" {
  name              = "/aws/lambda/${aws_lambda_function.policy_evaluation.function_name}"
  retention_in_days = 30
}

# ─── Lambda: Agent 4 — CaseSummary ───────────────────────────────────────────

resource "aws_lambda_function" "case_summary" {
  function_name    = "${var.prefix}-case-summary"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 180
  memory_size      = 512
  filename         = data.archive_file.case_summary.output_path
  source_code_hash = data.archive_file.case_summary.output_base64sha256

  environment {
    variables = merge(local.common_env, {
      BEDROCK_MODEL_ID = "anthropic.claude-3-7-sonnet-20250219-v1:0"
    })
  }
  tracing_config { mode = "Active" }
  tags = { Function = "case-summary" }
}

resource "aws_cloudwatch_log_group" "case_summary" {
  name              = "/aws/lambda/${aws_lambda_function.case_summary.function_name}"
  retention_in_days = 30
}

# ─── Lambda: Schema Init (run once to create Aurora tables) ──────────────────
# Invoke manually after first `terraform apply`:
#   aws lambda invoke --function-name case-triage-dev-aurora-schema-init out.json

resource "aws_lambda_function" "schema_init" {
  function_name    = "${var.prefix}-aurora-schema-init"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 300
  memory_size      = 256
  filename         = data.archive_file.schema_init.output_path
  source_code_hash = data.archive_file.schema_init.output_base64sha256

  environment {
    variables = {
      AURORA_CLUSTER_ARN = var.aurora_cluster_arn
      AURORA_SECRET_ARN  = var.aurora_secret_arn
      AURORA_DATABASE    = var.aurora_database
      ENVIRONMENT        = var.environment
      AWS_ACCOUNT_REGION = var.aws_region
    }
  }
  tags = { Function = "aurora-schema-init" }
}

resource "aws_cloudwatch_log_group" "schema_init" {
  name              = "/aws/lambda/${aws_lambda_function.schema_init.function_name}"
  retention_in_days = 14
}

# ─── Lambda: list_cases ────────────────────────────────────────────────────────

resource "aws_lambda_function" "list_cases" {
  function_name    = "${var.prefix}-list-cases"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 10
  memory_size      = 256
  filename         = data.archive_file.list_cases.output_path
  source_code_hash = data.archive_file.list_cases.output_base64sha256

  environment { variables = local.common_env }
  tracing_config { mode = "Active" }
  tags = { Function = "list-cases" }
}

resource "aws_cloudwatch_log_group" "list_cases" {
  name              = "/aws/lambda/${aws_lambda_function.list_cases.function_name}"
  retention_in_days = 30
}

# ─── Lambda: get_case_detail ──────────────────────────────────────────────────

resource "aws_lambda_function" "get_case_detail" {
  function_name    = "${var.prefix}-get-case-detail"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 30
  memory_size      = 512
  filename         = data.archive_file.get_case_detail.output_path
  source_code_hash = data.archive_file.get_case_detail.output_base64sha256

  environment { variables = local.common_env }
  tracing_config { mode = "Active" }
  tags = { Function = "get-case-detail" }
}

resource "aws_cloudwatch_log_group" "get_case_detail" {
  name              = "/aws/lambda/${aws_lambda_function.get_case_detail.function_name}"
  retention_in_days = 30
}

# ─── Lambda: record_decision ───────────────────────────────────────────────────

resource "aws_lambda_function" "record_decision" {
  function_name    = "${var.prefix}-record-decision"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.record_decision.output_path
  source_code_hash = data.archive_file.record_decision.output_base64sha256

  environment { variables = local.common_env }
  tracing_config { mode = "Active" }
  tags = { Function = "record-decision" }
}

resource "aws_cloudwatch_log_group" "record_decision" {
  name              = "/aws/lambda/${aws_lambda_function.record_decision.function_name}"
  retention_in_days = 30
}

# ─── Lambda: assign_case ──────────────────────────────────────────────────────

resource "aws_lambda_function" "assign_case" {
  function_name    = "${var.prefix}-assign-case"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 10
  memory_size      = 256
  filename         = data.archive_file.assign_case.output_path
  source_code_hash = data.archive_file.assign_case.output_base64sha256

  environment { variables = local.common_env }
  tracing_config { mode = "Active" }
  tags = { Function = "assign-case" }
}

resource "aws_cloudwatch_log_group" "assign_case" {
  name              = "/aws/lambda/${aws_lambda_function.assign_case.function_name}"
  retention_in_days = 30
}

# ─── Lambda: send_decision_email ───────────────────────────────────────────────

resource "aws_lambda_function" "send_decision_email" {
  function_name    = "${var.prefix}-send-decision-email"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.send_decision_email.output_path
  source_code_hash = data.archive_file.send_decision_email.output_base64sha256

  environment {
    variables = merge(local.common_env, { SENDER_EMAIL = var.ses_sender_email })
  }
  tracing_config { mode = "Active" }
  tags = { Function = "send-decision-email" }
}

resource "aws_cloudwatch_log_group" "send_decision_email" {
  name              = "/aws/lambda/${aws_lambda_function.send_decision_email.function_name}"
  retention_in_days = 30
}

# ─── Lambda: get_notifications ─────────────────────────────────────────────────

resource "aws_lambda_function" "get_notifications" {
  function_name    = "${var.prefix}-get-notifications"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 10
  memory_size      = 256
  filename         = data.archive_file.get_notifications.output_path
  source_code_hash = data.archive_file.get_notifications.output_base64sha256

  environment {
    variables = merge(local.common_env, { NOTIFICATIONS_TABLE = var.notifications_table_name })
  }
  tracing_config { mode = "Active" }
  tags = { Function = "get-notifications" }
}

resource "aws_cloudwatch_log_group" "get_notifications" {
  name              = "/aws/lambda/${aws_lambda_function.get_notifications.function_name}"
  retention_in_days = 30
}

# ─── Lambda: mark_notification_read ───────────────────────────────────────────

resource "aws_lambda_function" "mark_notification_read" {
  function_name    = "${var.prefix}-mark-notification-read"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 10
  memory_size      = 256
  filename         = data.archive_file.mark_notification_read.output_path
  source_code_hash = data.archive_file.mark_notification_read.output_base64sha256

  environment {
    variables = merge(local.common_env, { NOTIFICATIONS_TABLE = var.notifications_table_name })
  }
  tracing_config { mode = "Active" }
  tags = { Function = "mark-notification-read" }
}

resource "aws_cloudwatch_log_group" "mark_notification_read" {
  name              = "/aws/lambda/${aws_lambda_function.mark_notification_read.function_name}"
  retention_in_days = 30
}

# ─── Lambda: list_users ───────────────────────────────────────────────────────

resource "aws_lambda_function" "list_users" {
  function_name    = "${var.prefix}-list-users"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.list_users.output_path
  source_code_hash = data.archive_file.list_users.output_base64sha256

  environment {
    variables = merge(local.common_env, { COGNITO_USER_POOL_ID = var.cognito_user_pool_id })
  }
  tracing_config { mode = "Active" }
  tags = { Function = "list-users" }
}

resource "aws_cloudwatch_log_group" "list_users" {
  name              = "/aws/lambda/${aws_lambda_function.list_users.function_name}"
  retention_in_days = 30
}

# ─── Lambda: manage_user ──────────────────────────────────────────────────────

resource "aws_lambda_function" "manage_user" {
  function_name    = "${var.prefix}-manage-user"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.manage_user.output_path
  source_code_hash = data.archive_file.manage_user.output_base64sha256

  environment {
    variables = merge(local.common_env, { COGNITO_USER_POOL_ID = var.cognito_user_pool_id })
  }
  tracing_config { mode = "Active" }
  tags = { Function = "manage-user" }
}

resource "aws_cloudwatch_log_group" "manage_user" {
  name              = "/aws/lambda/${aws_lambda_function.manage_user.function_name}"
  retention_in_days = 30
}

# ─── Lambda: manage_policy ─────────────────────────────────────────────────────

resource "aws_lambda_function" "manage_policy" {
  function_name    = "${var.prefix}-manage-policy"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.manage_policy.output_path
  source_code_hash = data.archive_file.manage_policy.output_base64sha256

  environment { variables = local.common_env }
  tracing_config { mode = "Active" }
  tags = { Function = "manage-policy" }
}

resource "aws_cloudwatch_log_group" "manage_policy" {
  name              = "/aws/lambda/${aws_lambda_function.manage_policy.function_name}"
  retention_in_days = 30
}

# ─── Lambda: user_profile ─────────────────────────────────────────────────────

resource "aws_lambda_function" "user_profile" {
  function_name    = "${var.prefix}-user-profile"
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = local.runtime
  timeout          = 10
  memory_size      = 256
  filename         = data.archive_file.user_profile.output_path
  source_code_hash = data.archive_file.user_profile.output_base64sha256

  environment {
    variables = merge(local.common_env, { COGNITO_USER_POOL_ID = var.cognito_user_pool_id })
  }
  tracing_config { mode = "Active" }
  tags = { Function = "user-profile" }
}

resource "aws_cloudwatch_log_group" "user_profile" {
  name              = "/aws/lambda/${aws_lambda_function.user_profile.function_name}"
  retention_in_days = 30
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "app_init_invoke_arn"        { value = aws_lambda_function.app_init.invoke_arn }
output "app_init_function_name"     { value = aws_lambda_function.app_init.function_name }
output "app_finalize_invoke_arn"    { value = aws_lambda_function.app_finalize.invoke_arn }
output "app_finalize_function_name" { value = aws_lambda_function.app_finalize.function_name }
output "tech_validation_arn"        { value = aws_lambda_function.tech_validation.arn }
output "data_extraction_arn"        { value = aws_lambda_function.data_extraction.arn }
output "policy_evaluation_arn"      { value = aws_lambda_function.policy_evaluation.arn }
output "case_summary_arn"           { value = aws_lambda_function.case_summary.arn }
output "schema_init_function_name"  { value = aws_lambda_function.schema_init.function_name }
output "list_cases_invoke_arn"      { value = aws_lambda_function.list_cases.invoke_arn }
output "list_cases_function_name"   { value = aws_lambda_function.list_cases.function_name }
output "get_case_detail_invoke_arn" { value = aws_lambda_function.get_case_detail.invoke_arn }
output "get_case_detail_function_name" { value = aws_lambda_function.get_case_detail.function_name }
output "record_decision_invoke_arn" { value = aws_lambda_function.record_decision.invoke_arn }
output "record_decision_function_name" { value = aws_lambda_function.record_decision.function_name }
output "assign_case_invoke_arn"     { value = aws_lambda_function.assign_case.invoke_arn }
output "assign_case_function_name"  { value = aws_lambda_function.assign_case.function_name }
output "send_decision_email_invoke_arn" { value = aws_lambda_function.send_decision_email.invoke_arn }
output "send_decision_email_function_name" { value = aws_lambda_function.send_decision_email.function_name }
output "get_notifications_invoke_arn" { value = aws_lambda_function.get_notifications.invoke_arn }
output "get_notifications_function_name" { value = aws_lambda_function.get_notifications.function_name }
output "mark_notification_read_invoke_arn" { value = aws_lambda_function.mark_notification_read.invoke_arn }
output "mark_notification_read_function_name" { value = aws_lambda_function.mark_notification_read.function_name }
output "list_users_invoke_arn"      { value = aws_lambda_function.list_users.invoke_arn }
output "list_users_function_name"   { value = aws_lambda_function.list_users.function_name }
output "manage_user_invoke_arn"     { value = aws_lambda_function.manage_user.invoke_arn }
output "manage_user_function_name"  { value = aws_lambda_function.manage_user.function_name }
output "manage_policy_invoke_arn"   { value = aws_lambda_function.manage_policy.invoke_arn }
output "manage_policy_function_name" { value = aws_lambda_function.manage_policy.function_name }
output "user_profile_invoke_arn"    { value = aws_lambda_function.user_profile.invoke_arn }
output "user_profile_function_name" { value = aws_lambda_function.user_profile.function_name }
