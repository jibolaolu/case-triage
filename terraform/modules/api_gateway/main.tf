################################################################################
# API Gateway Module — Layer 1
# REST API with 3 intake endpoints:
#   POST /applications/init
#   PUT  /applications/upload  (presigned — handled client-side, no Lambda)
#   POST /applications/complete
################################################################################

variable "prefix"                            {}
variable "app_init_lambda_invoke_arn"        {}
variable "app_init_lambda_function_name"     {}
variable "app_finalize_lambda_invoke_arn"    {}
variable "app_finalize_lambda_function_name" {}
variable "environment"                       {}
variable "region"                            {}
variable "account_id"                        {}
variable "cognito_user_pool_arn"             { default = "" }
variable "enable_cognito_auth"              { default = true }


# ─── REST API ─────────────────────────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "intake" {
  name        = "${var.prefix}-intake-api"
  description = "Case Triage intake API — Layer 1 synchronous intake"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
  tags = {}
}

# ─── Resource: /applications ──────────────────────────────────────────────────

resource "aws_api_gateway_resource" "applications" {
  rest_api_id = aws_api_gateway_rest_api.intake.id
  parent_id   = aws_api_gateway_rest_api.intake.root_resource_id
  path_part   = "applications"
}

# ─── Cognito Authorizer ──────────────────────────────────────────────────────

resource "aws_api_gateway_authorizer" "cognito" {
  count         = var.enable_cognito_auth ? 1 : 0
  name          = "${var.prefix}-intake-cognito-auth"
  rest_api_id   = aws_api_gateway_rest_api.intake.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [var.cognito_user_pool_arn]
}

# ─── Resource: /applications/init ────────────────────────────────────────────

resource "aws_api_gateway_resource" "init" {
  rest_api_id = aws_api_gateway_rest_api.intake.id
  parent_id   = aws_api_gateway_resource.applications.id
  path_part   = "init"
}

resource "aws_api_gateway_method" "init_post" {
  rest_api_id   = aws_api_gateway_rest_api.intake.id
  resource_id   = aws_api_gateway_resource.init.id
  http_method   = "POST"
  authorization = var.enable_cognito_auth ? "COGNITO_USER_POOLS" : "NONE"
  authorizer_id = var.enable_cognito_auth ? aws_api_gateway_authorizer.cognito[0].id : null

  request_validator_id = aws_api_gateway_request_validator.body.id

  request_models = {
    "application/json" = aws_api_gateway_model.manifest.name
  }
}

resource "aws_api_gateway_integration" "init_post" {
  rest_api_id             = aws_api_gateway_rest_api.intake.id
  resource_id             = aws_api_gateway_resource.init.id
  http_method             = aws_api_gateway_method.init_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.app_init_lambda_invoke_arn
}

resource "aws_lambda_permission" "apigw_init" {
  statement_id  = "AllowAPIGatewayInvokeInit"
  action        = "lambda:InvokeFunction"
  function_name = var.app_init_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.intake.execution_arn}/*/*"
}

# ─── Resource: /applications/complete ────────────────────────────────────────

resource "aws_api_gateway_resource" "complete" {
  rest_api_id = aws_api_gateway_rest_api.intake.id
  parent_id   = aws_api_gateway_resource.applications.id
  path_part   = "complete"
}

resource "aws_api_gateway_method" "complete_post" {
  rest_api_id   = aws_api_gateway_rest_api.intake.id
  resource_id   = aws_api_gateway_resource.complete.id
  http_method   = "POST"
  authorization = var.enable_cognito_auth ? "COGNITO_USER_POOLS" : "NONE"
  authorizer_id = var.enable_cognito_auth ? aws_api_gateway_authorizer.cognito[0].id : null
  # No request_validator here — /complete only needs {"caseId": "..."} 
  # and the ManifestModel schema requires all 5 init fields which would
  # cause API Gateway to reject the request before Lambda is ever invoked.
}

resource "aws_api_gateway_integration" "complete_post" {
  rest_api_id             = aws_api_gateway_rest_api.intake.id
  resource_id             = aws_api_gateway_resource.complete.id
  http_method             = aws_api_gateway_method.complete_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.app_finalize_lambda_invoke_arn
}

resource "aws_lambda_permission" "apigw_complete" {
  statement_id  = "AllowAPIGatewayInvokeComplete"
  action        = "lambda:InvokeFunction"
  function_name = var.app_finalize_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.intake.execution_arn}/*/*"
}

# ─── Request Validator ────────────────────────────────────────────────────────

resource "aws_api_gateway_request_validator" "body" {
  rest_api_id           = aws_api_gateway_rest_api.intake.id
  name                  = "validate-body"
  validate_request_body = true
}

# ─── Manifest JSON Schema Model ───────────────────────────────────────────────

resource "aws_api_gateway_model" "manifest" {
  rest_api_id  = aws_api_gateway_rest_api.intake.id
  name         = "ManifestModel"
  content_type = "application/json"

  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "Manifest"
    type      = "object"
    required  = ["caseId", "orgId", "caseType", "submissionType", "submittedAt"]
    properties = {
      caseId         = { type = "string" }
      orgId          = { type = "string" }
      caseType       = { type = "string", enum = ["hardship-fund", "housing-support", "emergency-grant"] }
      submissionType = { type = "string", enum = ["NEW", "RESUBMISSION"] }
      submittedAt    = { type = "string" }
    }
  })
}

# ─── Gateway Responses (standardised error format) ────────────────────────────

resource "aws_api_gateway_gateway_response" "bad_request" {
  rest_api_id   = aws_api_gateway_rest_api.intake.id
  response_type = "BAD_REQUEST_BODY"
  status_code   = "400"

  response_templates = {
    "application/json" = jsonencode({
      error   = "Bad Request"
      message = "$context.error.validationErrorString"
    })
  }
}

resource "aws_api_gateway_gateway_response" "unauthorized" {
  rest_api_id   = aws_api_gateway_rest_api.intake.id
  response_type = "UNAUTHORIZED"
  status_code   = "401"

  response_templates = {
    "application/json" = jsonencode({
      error   = "Unauthorized"
      message = "Valid authentication token required"
    })
  }
}

resource "aws_api_gateway_gateway_response" "throttled" {
  rest_api_id   = aws_api_gateway_rest_api.intake.id
  response_type = "THROTTLED"
  status_code   = "429"

  response_templates = {
    "application/json" = jsonencode({
      error   = "Too Many Requests"
      message = "Rate limit exceeded. Please retry after a short delay."
    })
  }
}

# # Look up cases routes if they exist — won't fail if not yet deployed
# data "aws_api_gateway_resource" "cases_status" {
#   rest_api_id = aws_api_gateway_rest_api.intake.id
#   path        = "/cases/{caseId}/status"
# }
#
# data "aws_api_gateway_resource" "cases_pack" {
#   rest_api_id = aws_api_gateway_rest_api.intake.id
#   path        = "/cases/{caseId}/pack"
# }

# ─── Deployment & Stage ───────────────────────────────────────────────────────

resource "aws_api_gateway_deployment" "intake" {
  rest_api_id = aws_api_gateway_rest_api.intake.id

  triggers = {
    # Force redeploy on any resource/method/integration change
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.applications.id,
      aws_api_gateway_resource.init.id,
      aws_api_gateway_resource.complete.id,
      aws_api_gateway_method.init_post.id,
      aws_api_gateway_method.complete_post.id,
      aws_api_gateway_integration.init_post.id,
      aws_api_gateway_integration.complete_post.id,

    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "intake" {
  deployment_id = aws_api_gateway_deployment.intake.id
  rest_api_id   = aws_api_gateway_rest_api.intake.id
  stage_name    = var.environment

  # default_route_settings is HTTP API only, not REST API

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format          = "$context.requestId $context.status $context.error.message"
  }

  xray_tracing_enabled = true

  tags = { Stage = var.environment }
}

# Method-level throttling
resource "aws_api_gateway_method_settings" "throttle" {
  rest_api_id = aws_api_gateway_rest_api.intake.id
  stage_name  = aws_api_gateway_stage.intake.stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 100
    logging_level          = "INFO"
    data_trace_enabled     = false   # do not log request bodies in prod (PII)
    metrics_enabled        = true
  }
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/api-gateway/${var.prefix}-intake-api"
  retention_in_days = 30
}

# ─── Account-level CloudWatch role for API Gateway logging ────────────────────

resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "${var.prefix}-apigw-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn

  depends_on = [aws_iam_role_policy_attachment.api_gateway_cloudwatch]
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "base_url" {
  value = "https://${aws_api_gateway_rest_api.intake.id}.execute-api.${var.region}.amazonaws.com/${var.environment}"
}

output "api_id"      { value = aws_api_gateway_rest_api.intake.id }
output "stage_name"  { value = aws_api_gateway_stage.intake.stage_name }
output "root_resource_id" { value = aws_api_gateway_rest_api.intake.root_resource_id }
