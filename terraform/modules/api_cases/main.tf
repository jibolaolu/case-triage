################################################################################
# modules/api_cases/main.tf  — REST API v1 (aws_api_gateway_rest_api)
#
# Routes:
#   GET /cases/{caseId}/status  — polls DynamoDB for real pipeline status
#   GET /cases/{caseId}/pack    — returns presigned S3 URL for case pack JSON
#   Plus all new routes for list_cases, get_case_detail, record_decision, etc.
################################################################################

variable "prefix"                       {}
variable "region"                       {}
variable "account_id"                   {}
variable "api_gateway_id"               {}  # module.api_gateway.api_id
variable "api_gateway_root_resource_id" {}  # module.api_gateway.root_resource_id
variable "api_gateway_stage"            {}  # module.api_gateway.stage_name
variable "lambda_exec_role_arn"         {}
variable "dynamodb_table_name"          {}
variable "case_pack_bucket"             {}
variable "presign_ttl_seconds"          { default = 900 }

# New variables — Lambda invoke ARNs and function names from root module
variable "list_cases_invoke_arn"          {}
variable "list_cases_function_name"       {}
variable "get_case_detail_invoke_arn"     {}
variable "get_case_detail_function_name"  {}
variable "record_decision_invoke_arn"     {}
variable "record_decision_function_name"  {}
variable "assign_case_invoke_arn"         {}
variable "assign_case_function_name"      {}
variable "send_email_invoke_arn"          {}
variable "send_email_function_name"       {}
variable "get_notifications_invoke_arn"        {}
variable "get_notifications_function_name"     {}
variable "mark_notification_read_invoke_arn"   {}
variable "mark_notification_read_function_name" {}
variable "list_users_invoke_arn"          {}
variable "list_users_function_name"       {}
variable "manage_user_invoke_arn"         {}
variable "manage_user_function_name"      {}
variable "manage_policy_invoke_arn"       {}
variable "manage_policy_function_name"    {}
variable "user_profile_invoke_arn"        {}
variable "user_profile_function_name"     {}
variable "cognito_authorizer_id"          { default = "" }
variable "cognito_user_pool_arn"          { default = "" }
variable "enable_cognito_auth"            { default = true }

locals {
  fn_status = "${var.prefix}-get-case-status"
  fn_pack   = "${var.prefix}-get-case-pack"

  auth_type    = var.enable_cognito_auth ? "COGNITO_USER_POOLS" : "NONE"
  authorizer_id = var.enable_cognito_auth ? aws_api_gateway_authorizer.cognito[0].id : null
  cors_headers = "'Content-Type,x-api-key,Authorization'"
}

# ── Cognito authorizer ────────────────────────────────────────────────────────

resource "aws_api_gateway_authorizer" "cognito" {
  count         = var.enable_cognito_auth ? 1 : 0
  name          = "${var.prefix}-cognito-authorizer"
  rest_api_id   = var.api_gateway_id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [var.cognito_user_pool_arn]
}

# ── Zip Lambda source ─────────────────────────────────────────────────────────

data "archive_file" "get_case_status" {
  type        = "zip"
  source_file = "${path.module}/../../lambda_src/get_case_status/handler.py"
  output_path = "${path.module}/../../lambda_src/get_case_status.zip"
}

data "archive_file" "get_case_pack" {
  type        = "zip"
  source_file = "${path.module}/../../lambda_src/get_case_pack/handler.py"
  output_path = "${path.module}/../../lambda_src/get_case_pack.zip"
}

# ── Lambda functions ──────────────────────────────────────────────────────────

resource "aws_lambda_function" "get_case_status" {
  function_name    = local.fn_status
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.get_case_status.output_path
  source_code_hash = data.archive_file.get_case_status.output_base64sha256
  timeout          = 10
  memory_size      = 256
  environment {
    variables = {
      DYNAMODB_TABLE   = var.dynamodb_table_name
      CASE_PACK_BUCKET = var.case_pack_bucket
    }
  }
  tags = { Name = local.fn_status, ManagedBy = "terraform" }
}

resource "aws_lambda_function" "get_case_pack" {
  function_name    = local.fn_pack
  role             = var.lambda_exec_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.get_case_pack.output_path
  source_code_hash = data.archive_file.get_case_pack.output_base64sha256
  timeout          = 10
  memory_size      = 256
  environment {
    variables = {
      DYNAMODB_TABLE      = var.dynamodb_table_name
      CASE_PACK_BUCKET    = var.case_pack_bucket
      PRESIGN_TTL_SECONDS = tostring(var.presign_ttl_seconds)
    }
  }
  tags = { Name = local.fn_pack, ManagedBy = "terraform" }
}

resource "aws_cloudwatch_log_group" "get_case_status" {
  name              = "/aws/lambda/${local.fn_status}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "get_case_pack" {
  name              = "/aws/lambda/${local.fn_pack}"
  retention_in_days = 7
}

# ── API Gateway resources ─────────────────────────────────────────────────────
# /cases
resource "aws_api_gateway_resource" "cases" {
  rest_api_id = var.api_gateway_id
  parent_id   = var.api_gateway_root_resource_id
  path_part   = "cases"
}

# /cases/{caseId}
resource "aws_api_gateway_resource" "case_id" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.cases.id
  path_part   = "{caseId}"
}

# /cases/{caseId}/status
resource "aws_api_gateway_resource" "status" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.case_id.id
  path_part   = "status"
}

# /cases/{caseId}/pack
resource "aws_api_gateway_resource" "pack" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.case_id.id
  path_part   = "pack"
}

# /cases/{caseId}/decision
resource "aws_api_gateway_resource" "decision" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.case_id.id
  path_part   = "decision"
}

# /cases/{caseId}/assign
resource "aws_api_gateway_resource" "assign" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.case_id.id
  path_part   = "assign"
}

# /cases/{caseId}/email
resource "aws_api_gateway_resource" "email" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.case_id.id
  path_part   = "email"
}

# /notifications
resource "aws_api_gateway_resource" "notifications" {
  rest_api_id = var.api_gateway_id
  parent_id   = var.api_gateway_root_resource_id
  path_part   = "notifications"
}

# /notifications/{notificationId}
resource "aws_api_gateway_resource" "notification_id" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.notifications.id
  path_part   = "{notificationId}"
}

# /notifications/{notificationId}/read
resource "aws_api_gateway_resource" "notification_read" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.notification_id.id
  path_part   = "read"
}

# /admin
resource "aws_api_gateway_resource" "admin" {
  rest_api_id = var.api_gateway_id
  parent_id   = var.api_gateway_root_resource_id
  path_part   = "admin"
}

# /admin/users
resource "aws_api_gateway_resource" "admin_users" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.admin.id
  path_part   = "users"
}

# /admin/users/{userId}
resource "aws_api_gateway_resource" "admin_user_id" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.admin_users.id
  path_part   = "{userId}"
}

# /admin/users/{userId}/role
resource "aws_api_gateway_resource" "admin_user_role" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.admin_user_id.id
  path_part   = "role"
}

# /admin/users/{userId}/status
resource "aws_api_gateway_resource" "admin_user_status" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.admin_user_id.id
  path_part   = "status"
}

# /admin/policies
resource "aws_api_gateway_resource" "admin_policies" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.admin.id
  path_part   = "policies"
}

# /admin/policies/{policyId}
resource "aws_api_gateway_resource" "admin_policy_id" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.admin_policies.id
  path_part   = "{policyId}"
}

# /users
resource "aws_api_gateway_resource" "users" {
  rest_api_id = var.api_gateway_id
  parent_id   = var.api_gateway_root_resource_id
  path_part   = "users"
}

# /users/me
resource "aws_api_gateway_resource" "users_me" {
  rest_api_id = var.api_gateway_id
  parent_id   = aws_api_gateway_resource.users.id
  path_part   = "me"
}

# ── GET /cases/{caseId}/status ────────────────────────────────────────────────

resource "aws_api_gateway_method" "get_status" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.status.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_status" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.status.id
  http_method             = aws_api_gateway_method.get_status.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_case_status.invoke_arn
}

resource "aws_api_gateway_method" "options_status" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.status.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_status" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.status.id
  http_method       = aws_api_gateway_method.options_status.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_status_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.status.id
  http_method = aws_api_gateway_method.options_status.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_status" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.status.id
  http_method = aws_api_gateway_method.options_status.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,x-api-key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_status]
}

# ── GET /cases/{caseId}/pack ──────────────────────────────────────────────────

resource "aws_api_gateway_method" "get_pack" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.pack.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_pack" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.pack.id
  http_method             = aws_api_gateway_method.get_pack.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_case_pack.invoke_arn
}

resource "aws_api_gateway_method" "options_pack" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.pack.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_pack" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.pack.id
  http_method       = aws_api_gateway_method.options_pack.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_pack_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.pack.id
  http_method = aws_api_gateway_method.options_pack.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_pack" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.pack.id
  http_method = aws_api_gateway_method.options_pack.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,x-api-key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_pack]
}

# ── New routes (with Cognito auth when configured) ────────────────────────────

# 1. GET /cases → list_cases
resource "aws_api_gateway_method" "list_cases" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.cases.id
  http_method   = "GET"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "list_cases" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.cases.id
  http_method             = aws_api_gateway_method.list_cases.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.list_cases_invoke_arn
}

resource "aws_api_gateway_method" "options_cases" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.cases.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_cases" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.cases.id
  http_method       = aws_api_gateway_method.options_cases.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_cases_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.cases.id
  http_method = aws_api_gateway_method.options_cases.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_cases" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.cases.id
  http_method = aws_api_gateway_method.options_cases.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_cases]
}

# 2. GET /cases/{caseId} → get_case_detail
resource "aws_api_gateway_method" "get_case_detail" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.case_id.id
  http_method   = "GET"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "get_case_detail" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.case_id.id
  http_method             = aws_api_gateway_method.get_case_detail.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.get_case_detail_invoke_arn
}

resource "aws_api_gateway_method" "options_case_id" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.case_id.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_case_id" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.case_id.id
  http_method       = aws_api_gateway_method.options_case_id.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_case_id_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.case_id.id
  http_method = aws_api_gateway_method.options_case_id.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_case_id" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.case_id.id
  http_method = aws_api_gateway_method.options_case_id.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_case_id]
}

# 3. POST /cases/{caseId}/decision → record_decision
resource "aws_api_gateway_method" "record_decision" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.decision.id
  http_method   = "POST"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "record_decision" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.decision.id
  http_method             = aws_api_gateway_method.record_decision.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.record_decision_invoke_arn
}

resource "aws_api_gateway_method" "options_decision" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.decision.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_decision" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.decision.id
  http_method       = aws_api_gateway_method.options_decision.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_decision_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.decision.id
  http_method = aws_api_gateway_method.options_decision.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_decision" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.decision.id
  http_method = aws_api_gateway_method.options_decision.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_decision]
}

# 4. PUT /cases/{caseId}/assign → assign_case
resource "aws_api_gateway_method" "assign_case" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.assign.id
  http_method   = "PUT"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "assign_case" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.assign.id
  http_method             = aws_api_gateway_method.assign_case.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.assign_case_invoke_arn
}

resource "aws_api_gateway_method" "options_assign" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.assign.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_assign" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.assign.id
  http_method       = aws_api_gateway_method.options_assign.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_assign_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.assign.id
  http_method = aws_api_gateway_method.options_assign.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_assign" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.assign.id
  http_method = aws_api_gateway_method.options_assign.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'PUT,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_assign]
}

# 5. POST /cases/{caseId}/email → send_email
resource "aws_api_gateway_method" "send_email" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.email.id
  http_method   = "POST"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "send_email" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.email.id
  http_method             = aws_api_gateway_method.send_email.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.send_email_invoke_arn
}

resource "aws_api_gateway_method" "options_email" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.email.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_email" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.email.id
  http_method       = aws_api_gateway_method.options_email.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_email_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.email.id
  http_method = aws_api_gateway_method.options_email.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_email" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.email.id
  http_method = aws_api_gateway_method.options_email.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_email]
}

# 6. GET /notifications → get_notifications
resource "aws_api_gateway_method" "get_notifications" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.notifications.id
  http_method   = "GET"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "get_notifications" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.notifications.id
  http_method             = aws_api_gateway_method.get_notifications.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.get_notifications_invoke_arn
}

resource "aws_api_gateway_method" "options_notifications" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.notifications.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_notifications" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.notifications.id
  http_method       = aws_api_gateway_method.options_notifications.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_notifications_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.notifications.id
  http_method = aws_api_gateway_method.options_notifications.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_notifications" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.notifications.id
  http_method = aws_api_gateway_method.options_notifications.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_notifications]
}

# 7. PUT /notifications/{notificationId}/read → mark_notification_read
resource "aws_api_gateway_method" "mark_notification_read" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.notification_read.id
  http_method   = "PUT"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "mark_notification_read" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.notification_read.id
  http_method             = aws_api_gateway_method.mark_notification_read.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.mark_notification_read_invoke_arn
}

resource "aws_api_gateway_method" "options_notification_read" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.notification_read.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_notification_read" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.notification_read.id
  http_method       = aws_api_gateway_method.options_notification_read.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_notification_read_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.notification_read.id
  http_method = aws_api_gateway_method.options_notification_read.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_notification_read" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.notification_read.id
  http_method = aws_api_gateway_method.options_notification_read.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'PUT,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_notification_read]
}

# 8–12. /admin/users routes
# GET /admin/users → list_users
resource "aws_api_gateway_method" "list_users" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_users.id
  http_method   = "GET"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "list_users" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.admin_users.id
  http_method             = aws_api_gateway_method.list_users.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.list_users_invoke_arn
}

# POST /admin/users → manage_user
resource "aws_api_gateway_method" "manage_user_post" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_users.id
  http_method   = "POST"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "manage_user_post" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.admin_users.id
  http_method             = aws_api_gateway_method.manage_user_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.manage_user_invoke_arn
}

resource "aws_api_gateway_method" "options_admin_users" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_users.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_admin_users" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.admin_users.id
  http_method       = aws_api_gateway_method.options_admin_users.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_admin_users_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.admin_users.id
  http_method = aws_api_gateway_method.options_admin_users.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_admin_users" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.admin_users.id
  http_method = aws_api_gateway_method.options_admin_users.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_admin_users]
}

# PUT /admin/users/{userId}/role → manage_user
resource "aws_api_gateway_method" "manage_user_role" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_user_role.id
  http_method   = "PUT"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "manage_user_role" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.admin_user_role.id
  http_method             = aws_api_gateway_method.manage_user_role.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.manage_user_invoke_arn
}

resource "aws_api_gateway_method" "options_admin_user_role" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_user_role.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_admin_user_role" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.admin_user_role.id
  http_method       = aws_api_gateway_method.options_admin_user_role.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_admin_user_role_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.admin_user_role.id
  http_method = aws_api_gateway_method.options_admin_user_role.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_admin_user_role" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.admin_user_role.id
  http_method = aws_api_gateway_method.options_admin_user_role.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'PUT,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_admin_user_role]
}

# PUT /admin/users/{userId}/status → manage_user
resource "aws_api_gateway_method" "manage_user_status" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_user_status.id
  http_method   = "PUT"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "manage_user_status" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.admin_user_status.id
  http_method             = aws_api_gateway_method.manage_user_status.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.manage_user_invoke_arn
}

resource "aws_api_gateway_method" "options_admin_user_status" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_user_status.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_admin_user_status" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.admin_user_status.id
  http_method       = aws_api_gateway_method.options_admin_user_status.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_admin_user_status_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.admin_user_status.id
  http_method = aws_api_gateway_method.options_admin_user_status.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_admin_user_status" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.admin_user_status.id
  http_method = aws_api_gateway_method.options_admin_user_status.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'PUT,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_admin_user_status]
}

# DELETE /admin/users/{userId} → manage_user
resource "aws_api_gateway_method" "manage_user_delete" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_user_id.id
  http_method   = "DELETE"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "manage_user_delete" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.admin_user_id.id
  http_method             = aws_api_gateway_method.manage_user_delete.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.manage_user_invoke_arn
}

resource "aws_api_gateway_method" "options_admin_user_id" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_user_id.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_admin_user_id" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.admin_user_id.id
  http_method       = aws_api_gateway_method.options_admin_user_id.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_admin_user_id_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.admin_user_id.id
  http_method = aws_api_gateway_method.options_admin_user_id.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_admin_user_id" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.admin_user_id.id
  http_method = aws_api_gateway_method.options_admin_user_id.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_admin_user_id]
}

# 13–17. /admin/policies routes
# GET /admin/policies → manage_policy
resource "aws_api_gateway_method" "manage_policy_get_list" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_policies.id
  http_method   = "GET"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "manage_policy_get_list" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.admin_policies.id
  http_method             = aws_api_gateway_method.manage_policy_get_list.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.manage_policy_invoke_arn
}

# POST /admin/policies → manage_policy
resource "aws_api_gateway_method" "manage_policy_post" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_policies.id
  http_method   = "POST"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "manage_policy_post" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.admin_policies.id
  http_method             = aws_api_gateway_method.manage_policy_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.manage_policy_invoke_arn
}

resource "aws_api_gateway_method" "options_admin_policies" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_policies.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_admin_policies" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.admin_policies.id
  http_method       = aws_api_gateway_method.options_admin_policies.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_admin_policies_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.admin_policies.id
  http_method = aws_api_gateway_method.options_admin_policies.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_admin_policies" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.admin_policies.id
  http_method = aws_api_gateway_method.options_admin_policies.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_admin_policies]
}

# GET /admin/policies/{policyId} → manage_policy
resource "aws_api_gateway_method" "manage_policy_get" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_policy_id.id
  http_method   = "GET"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "manage_policy_get" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.admin_policy_id.id
  http_method             = aws_api_gateway_method.manage_policy_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.manage_policy_invoke_arn
}

# PUT /admin/policies/{policyId} → manage_policy
resource "aws_api_gateway_method" "manage_policy_put" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_policy_id.id
  http_method   = "PUT"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "manage_policy_put" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.admin_policy_id.id
  http_method             = aws_api_gateway_method.manage_policy_put.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.manage_policy_invoke_arn
}

# DELETE /admin/policies/{policyId} → manage_policy
resource "aws_api_gateway_method" "manage_policy_delete" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_policy_id.id
  http_method   = "DELETE"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "manage_policy_delete" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.admin_policy_id.id
  http_method             = aws_api_gateway_method.manage_policy_delete.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.manage_policy_invoke_arn
}

resource "aws_api_gateway_method" "options_admin_policy_id" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.admin_policy_id.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_admin_policy_id" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.admin_policy_id.id
  http_method       = aws_api_gateway_method.options_admin_policy_id.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_admin_policy_id_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.admin_policy_id.id
  http_method = aws_api_gateway_method.options_admin_policy_id.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_admin_policy_id" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.admin_policy_id.id
  http_method = aws_api_gateway_method.options_admin_policy_id.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'GET,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_admin_policy_id]
}

# 18–19. GET/PUT /users/me → user_profile
resource "aws_api_gateway_method" "user_profile_get" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.users_me.id
  http_method   = "GET"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "user_profile_get" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.users_me.id
  http_method             = aws_api_gateway_method.user_profile_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.user_profile_invoke_arn
}

resource "aws_api_gateway_method" "user_profile_put" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.users_me.id
  http_method   = "PUT"
  authorization = local.auth_type
  authorizer_id = local.authorizer_id
}

resource "aws_api_gateway_integration" "user_profile_put" {
  rest_api_id             = var.api_gateway_id
  resource_id             = aws_api_gateway_resource.users_me.id
  http_method             = aws_api_gateway_method.user_profile_put.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.user_profile_invoke_arn
}

resource "aws_api_gateway_method" "options_users_me" {
  rest_api_id   = var.api_gateway_id
  resource_id   = aws_api_gateway_resource.users_me.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_users_me" {
  rest_api_id       = var.api_gateway_id
  resource_id       = aws_api_gateway_resource.users_me.id
  http_method       = aws_api_gateway_method.options_users_me.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_users_me_200" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.users_me.id
  http_method = aws_api_gateway_method.options_users_me.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_users_me" {
  rest_api_id = var.api_gateway_id
  resource_id = aws_api_gateway_resource.users_me.id
  http_method = aws_api_gateway_method.options_users_me.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = local.cors_headers
    "method.response.header.Access-Control-Allow-Methods" = "'GET,PUT,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.options_users_me]
}

# ── Lambda invoke permissions ─────────────────────────────────────────────────
# External Lambdas (from root module) — one permission per function with wildcard

resource "aws_lambda_permission" "apigw_list_cases" {
  statement_id  = "AllowAPIGatewayInvokeListCases"
  action        = "lambda:InvokeFunction"
  function_name = var.list_cases_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

resource "aws_lambda_permission" "apigw_get_case_detail" {
  statement_id  = "AllowAPIGatewayInvokeGetCaseDetail"
  action        = "lambda:InvokeFunction"
  function_name = var.get_case_detail_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

resource "aws_lambda_permission" "apigw_record_decision" {
  statement_id  = "AllowAPIGatewayInvokeRecordDecision"
  action        = "lambda:InvokeFunction"
  function_name = var.record_decision_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

resource "aws_lambda_permission" "apigw_assign_case" {
  statement_id  = "AllowAPIGatewayInvokeAssignCase"
  action        = "lambda:InvokeFunction"
  function_name = var.assign_case_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

resource "aws_lambda_permission" "apigw_send_email" {
  statement_id  = "AllowAPIGatewayInvokeSendEmail"
  action        = "lambda:InvokeFunction"
  function_name = var.send_email_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

resource "aws_lambda_permission" "apigw_get_notifications" {
  statement_id  = "AllowAPIGatewayInvokeGetNotifications"
  action        = "lambda:InvokeFunction"
  function_name = var.get_notifications_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

resource "aws_lambda_permission" "apigw_mark_notification_read" {
  statement_id  = "AllowAPIGatewayInvokeMarkNotificationRead"
  action        = "lambda:InvokeFunction"
  function_name = var.mark_notification_read_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

resource "aws_lambda_permission" "apigw_list_users" {
  statement_id  = "AllowAPIGatewayInvokeListUsers"
  action        = "lambda:InvokeFunction"
  function_name = var.list_users_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

resource "aws_lambda_permission" "apigw_manage_user" {
  statement_id  = "AllowAPIGatewayInvokeManageUser"
  action        = "lambda:InvokeFunction"
  function_name = var.manage_user_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

resource "aws_lambda_permission" "apigw_manage_policy" {
  statement_id  = "AllowAPIGatewayInvokeManagePolicy"
  action        = "lambda:InvokeFunction"
  function_name = var.manage_policy_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

resource "aws_lambda_permission" "apigw_user_profile" {
  statement_id  = "AllowAPIGatewayInvokeUserProfile"
  action        = "lambda:InvokeFunction"
  function_name = var.user_profile_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

# Internal Lambdas (get_case_status, get_case_pack)
resource "aws_lambda_permission" "apigw_get_case_status" {
  statement_id  = "AllowAPIGatewayInvokeStatus"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_case_status.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

resource "aws_lambda_permission" "apigw_get_case_pack" {
  statement_id  = "AllowAPIGatewayInvokePack"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_case_pack.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${var.api_gateway_id}/*"
}

# ── Redeploy existing stage ───────────────────────────────────────────────────

resource "aws_api_gateway_deployment" "cases" {
  rest_api_id = var.api_gateway_id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.cases.id,
      aws_api_gateway_resource.case_id.id,
      aws_api_gateway_resource.status.id,
      aws_api_gateway_resource.pack.id,
      aws_api_gateway_resource.decision.id,
      aws_api_gateway_resource.assign.id,
      aws_api_gateway_resource.email.id,
      aws_api_gateway_resource.notifications.id,
      aws_api_gateway_resource.notification_id.id,
      aws_api_gateway_resource.notification_read.id,
      aws_api_gateway_resource.admin.id,
      aws_api_gateway_resource.admin_users.id,
      aws_api_gateway_resource.admin_user_id.id,
      aws_api_gateway_resource.admin_user_role.id,
      aws_api_gateway_resource.admin_user_status.id,
      aws_api_gateway_resource.admin_policies.id,
      aws_api_gateway_resource.admin_policy_id.id,
      aws_api_gateway_resource.users.id,
      aws_api_gateway_resource.users_me.id,
      aws_api_gateway_integration.get_status.id,
      aws_api_gateway_integration.get_pack.id,
      aws_api_gateway_integration.list_cases.id,
      aws_api_gateway_integration.get_case_detail.id,
      aws_api_gateway_integration.record_decision.id,
      aws_api_gateway_integration.assign_case.id,
      aws_api_gateway_integration.send_email.id,
      aws_api_gateway_integration.get_notifications.id,
      aws_api_gateway_integration.mark_notification_read.id,
      aws_api_gateway_integration.list_users.id,
      aws_api_gateway_integration.manage_user_post.id,
      aws_api_gateway_integration.manage_user_role.id,
      aws_api_gateway_integration.manage_user_status.id,
      aws_api_gateway_integration.manage_user_delete.id,
      aws_api_gateway_integration.manage_policy_get_list.id,
      aws_api_gateway_integration.manage_policy_post.id,
      aws_api_gateway_integration.manage_policy_get.id,
      aws_api_gateway_integration.manage_policy_put.id,
      aws_api_gateway_integration.manage_policy_delete.id,
      aws_api_gateway_integration.user_profile_get.id,
      aws_api_gateway_integration.user_profile_put.id,
    ]))
  }

  lifecycle { create_before_destroy = true }

  depends_on = [
    aws_api_gateway_integration.get_status,
    aws_api_gateway_integration.get_pack,
    aws_api_gateway_integration.options_status,
    aws_api_gateway_integration.options_pack,
    aws_api_gateway_integration_response.options_status,
    aws_api_gateway_integration_response.options_pack,
    aws_api_gateway_integration.list_cases,
    aws_api_gateway_integration.get_case_detail,
    aws_api_gateway_integration.record_decision,
    aws_api_gateway_integration.assign_case,
    aws_api_gateway_integration.send_email,
    aws_api_gateway_integration.get_notifications,
    aws_api_gateway_integration.mark_notification_read,
    aws_api_gateway_integration.list_users,
    aws_api_gateway_integration.manage_user_post,
    aws_api_gateway_integration.manage_user_role,
    aws_api_gateway_integration.manage_user_status,
    aws_api_gateway_integration.manage_user_delete,
    aws_api_gateway_integration.manage_policy_get_list,
    aws_api_gateway_integration.manage_policy_post,
    aws_api_gateway_integration.manage_policy_get,
    aws_api_gateway_integration.manage_policy_put,
    aws_api_gateway_integration.manage_policy_delete,
    aws_api_gateway_integration.user_profile_get,
    aws_api_gateway_integration.user_profile_put,
  ]
}

resource "null_resource" "update_stage_deployment" {
  triggers = {
    deployment_id = aws_api_gateway_deployment.cases.id
  }

  provisioner "local-exec" {
    command = <<EOF
aws apigateway update-stage \
  --rest-api-id ${var.api_gateway_id} \
  --stage-name ${var.api_gateway_stage} \
  --patch-operations op=replace,path=/deploymentId,value=${aws_api_gateway_deployment.cases.id} \
  --region ${var.region}
EOF
  }

  depends_on = [aws_api_gateway_deployment.cases]
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "status_endpoint" {
  value = "https://${var.api_gateway_id}.execute-api.${var.region}.amazonaws.com/${var.api_gateway_stage}/cases/{caseId}/status"
}
output "pack_endpoint" {
  value = "https://${var.api_gateway_id}.execute-api.${var.region}.amazonaws.com/${var.api_gateway_stage}/cases/{caseId}/pack"
}
