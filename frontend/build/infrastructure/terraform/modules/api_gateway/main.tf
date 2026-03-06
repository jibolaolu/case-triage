resource "aws_apigatewayv2_api" "main" {
  name          = "${var.name_prefix}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type", "Idempotency-Key"]
    max_age       = 3600
  }
  tags = { Name = "${var.name_prefix}-api" }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"
  integration_uri  = var.lambda_invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "ANY /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorizer_id      = var.cognito_user_pool_arn != "" ? aws_apigatewayv2_authorizer.cognito[0].id : null
  authorization_type = var.cognito_user_pool_arn != "" ? "JWT" : null
}

resource "aws_apigatewayv2_route" "root" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "ANY /"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorizer_id      = var.cognito_user_pool_arn != "" ? aws_apigatewayv2_authorizer.cognito[0].id : null
  authorization_type = var.cognito_user_pool_arn != "" ? "JWT" : null
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({ requestId = "$context.requestId", ip = "$context.identity.sourceIp", requestTime = "$context.requestTime", httpMethod = "$context.httpMethod", routeKey = "$context.routeKey", status = "$context.status" })
  }
  default_route_settings {
    throttling_burst_limit = 500
    throttling_rate_limit  = 1000
  }
  tags = { Name = "${var.name_prefix}-api-default" }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${var.name_prefix}-api"
  retention_in_days  = 14
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = var.lambda_function_name
  principal      = "apigateway.amazonaws.com"
  source_arn     = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# Optional: Cognito authorizer (only if cognito_user_pool_arn is set)
resource "aws_apigatewayv2_authorizer" "cognito" {
  count           = var.cognito_user_pool_arn != "" ? 1 : 0
  api_id          = aws_apigatewayv2_api.main.id
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name = "${var.name_prefix}-cognito"
  jwt_configuration {
    audience = [] # set if required
    issuer   = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${split("/", var.cognito_user_pool_arn)[1]}"
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
