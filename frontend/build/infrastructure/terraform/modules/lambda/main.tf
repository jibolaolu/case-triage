# Lambda: API router (single handler that routes by path), Application init/finalize, Agent Lambdas, Failure handler
# Code is zipped from api_source_path and agents_source_path; for simplicity we use a single placeholder zip here.
# In production, use data "archive_file" or CI to upload zip to S3 and reference s3_bucket/s3_key.

data "archive_file" "api_placeholder" {
  type        = "zip"
  output_path = "${path.module}/api_placeholder.zip"
  source {
    content  = "placeholder"
    filename = "placeholder.txt"
  }
}

data "archive_file" "agents_placeholder" {
  type        = "zip"
  output_path = "${path.module}/agents_placeholder.zip"
  source {
    content  = "placeholder"
    filename = "placeholder.txt"
  }
}

locals {
  api_zip    = data.archive_file.api_placeholder.output_path
  agents_zip = data.archive_file.agents_placeholder.output_path
}

resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

locals {
  dynamodb_resources = concat(
    ["arn:aws:dynamodb:*:*:table/${var.case_state_table_name}", "arn:aws:dynamodb:*:*:table/${var.idempotency_table_name}"],
    var.event_log_table_name != "" ? ["arn:aws:dynamodb:*:*:table/${var.event_log_table_name}"] : []
  )
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.name_prefix}-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query", "dynamodb:BatchWriteItem"]
        Resource = local.dynamodb_resources
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.db_secret_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"]
        Resource = ["arn:aws:s3:::*-applicant-intake-s3-*", "arn:aws:s3:::*-applicant-intake-s3-*/*", "arn:aws:s3:::*-policy-definitions", "arn:aws:s3:::*-policy-definitions/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["textract:AnalyzeDocument", "textract:GetDocumentAnalysis", "textract:StartDocumentAnalysis"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = [aws_sqs_queue.api_dlq.arn, aws_sqs_queue.agents_dlq.arn]
      },
      {
        Effect   = "Allow"
        Action   = [
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminAddUserToGroup",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminListGroupsForUser",
          "cognito-idp:AdminSetUserMFAPreference"
        ]
        Resource = var.cognito_user_pool_id != "" ? ["arn:aws:cognito-idp:*:*:userpool/${var.cognito_user_pool_id}"] : []
      }
    ]
  })
}

# Lambda DLQs (async invocation failures)
resource "aws_sqs_queue" "api_dlq" {
  name = "${var.name_prefix}-api-lambda-dlq"
  message_retention_seconds = 1209600
  tags = { Name = "${var.name_prefix}-api-lambda-dlq" }
}

resource "aws_sqs_queue" "agents_dlq" {
  name = "${var.name_prefix}-agents-lambda-dlq"
  message_retention_seconds = 1209600
  tags = { Name = "${var.name_prefix}-agents-lambda-dlq" }
}

resource "aws_lambda_function" "api" {
  function_name = "${var.name_prefix}-api"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  runtime       = var.runtime
  filename      = local.api_zip
  source_code_hash = filebase64sha256(local.api_zip)
  timeout       = 30
  memory_size   = 512
  dead_letter_config { target_arn = aws_sqs_queue.api_dlq.arn }
  tracing_config { mode = "Active" }
  vpc_config {
    subnet_ids         = var.vpc_config.subnet_ids
    security_group_ids = var.vpc_config.security_group_ids
  }
  environment {
    variables = {
      ENVIRONMENT            = var.environment
      CASE_STATE_TABLE       = var.case_state_table_name
      IDEMPOTENCY_TABLE     = var.idempotency_table_name
      EVENT_LOG_TABLE       = var.event_log_table_name
      DB_PROXY_ENDPOINT     = var.db_proxy_endpoint
      DB_SECRET_ARN         = var.db_secret_arn
      EVENT_BUS_NAME        = var.event_bus_name
      COGNITO_USER_POOL_ID  = var.cognito_user_pool_id
      LOG_LEVEL             = "INFO"
    }
  }
  tags = { Name = "${var.name_prefix}-api" }
}

resource "aws_lambda_function" "application_init" {
  function_name = "${var.name_prefix}-application-init"
  role          = aws_iam_role.lambda.arn
  handler       = "applicationInit.handler"
  runtime       = var.runtime
  filename      = local.api_zip
  source_code_hash = filebase64sha256(local.api_zip)
  timeout       = 30
  memory_size   = 512
  dead_letter_config { target_arn = aws_sqs_queue.api_dlq.arn }
  tracing_config { mode = "Active" }
  environment {
    variables = {
      ENVIRONMENT = var.environment
      CASE_STATE_TABLE = var.case_state_table_name
      IDEMPOTENCY_TABLE = var.idempotency_table_name
      DB_PROXY_ENDPOINT = var.db_proxy_endpoint
      DB_SECRET_ARN = var.db_secret_arn
    }
  }
  tags = { Name = "${var.name_prefix}-application-init" }
}

resource "aws_lambda_function" "application_finalize" {
  function_name = "${var.name_prefix}-application-finalize"
  role          = aws_iam_role.lambda.arn
  handler       = "applicationFinalize.handler"
  runtime       = var.runtime
  filename      = local.api_zip
  source_code_hash = filebase64sha256(local.api_zip)
  timeout       = 60
  memory_size   = 512
  dead_letter_config { target_arn = aws_sqs_queue.api_dlq.arn }
  tracing_config { mode = "Active" }
  environment {
    variables = {
      ENVIRONMENT = var.environment
      CASE_STATE_TABLE = var.case_state_table_name
      EVENT_LOG_TABLE  = var.event_log_table_name
      EVENT_BUS_NAME = var.event_bus_name
      DB_PROXY_ENDPOINT = var.db_proxy_endpoint
      DB_SECRET_ARN = var.db_secret_arn
    }
  }
  tags = { Name = "${var.name_prefix}-application-finalize" }
}

resource "aws_lambda_function" "failure_handler" {
  function_name = "${var.name_prefix}-failure-handler"
  role          = aws_iam_role.lambda.arn
  handler       = "failureHandler.handler"
  runtime       = var.runtime
  filename      = local.agents_zip
  source_code_hash = filebase64sha256(local.agents_zip)
  timeout       = 30
  memory_size   = 256
  dead_letter_config { target_arn = aws_sqs_queue.agents_dlq.arn }
  tracing_config { mode = "Active" }
  environment {
    variables = {
      ENVIRONMENT = var.environment
      CASE_STATE_TABLE = var.case_state_table_name
      EVENT_LOG_TABLE  = var.event_log_table_name
      EVENT_BUS_NAME = var.event_bus_name
      DB_PROXY_ENDPOINT = var.db_proxy_endpoint
      DB_SECRET_ARN = var.db_secret_arn
    }
  }
  tags = { Name = "${var.name_prefix}-failure-handler" }
}

# Agent Lambdas (stubs; same zip for all for now)
resource "aws_lambda_function" "document_validation" {
  function_name = "${var.name_prefix}-document-validation-agent"
  role          = aws_iam_role.lambda.arn
  handler       = "documentValidation.handler"
  runtime       = var.runtime
  filename      = local.agents_zip
  source_code_hash = filebase64sha256(local.agents_zip)
  timeout       = 300
  memory_size   = 1024
  dead_letter_config { target_arn = aws_sqs_queue.agents_dlq.arn }
  tracing_config { mode = "Active" }
  environment {
    variables = {
      ENVIRONMENT = var.environment
      CASE_STATE_TABLE = var.case_state_table_name
      DB_PROXY_ENDPOINT = var.db_proxy_endpoint
      DB_SECRET_ARN = var.db_secret_arn
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }
  tags = { Name = "${var.name_prefix}-document-validation-agent" }
}

resource "aws_lambda_function" "data_extraction" {
  function_name = "${var.name_prefix}-data-extraction-agent"
  role          = aws_iam_role.lambda.arn
  handler       = "dataExtraction.handler"
  runtime       = var.runtime
  filename      = local.agents_zip
  source_code_hash = filebase64sha256(local.agents_zip)
  timeout       = 900
  memory_size   = 2048
  dead_letter_config { target_arn = aws_sqs_queue.agents_dlq.arn }
  tracing_config { mode = "Active" }
  environment {
    variables = {
      ENVIRONMENT = var.environment
      CASE_STATE_TABLE = var.case_state_table_name
      DB_PROXY_ENDPOINT = var.db_proxy_endpoint
      DB_SECRET_ARN = var.db_secret_arn
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }
  tags = { Name = "${var.name_prefix}-data-extraction-agent" }
}

resource "aws_lambda_function" "policy_evaluation" {
  function_name = "${var.name_prefix}-policy-evaluation-agent"
  role          = aws_iam_role.lambda.arn
  handler       = "policyEvaluation.handler"
  runtime       = var.runtime
  filename      = local.agents_zip
  source_code_hash = filebase64sha256(local.agents_zip)
  timeout       = 300
  memory_size   = 1024
  dead_letter_config { target_arn = aws_sqs_queue.agents_dlq.arn }
  tracing_config { mode = "Active" }
  environment {
    variables = {
      ENVIRONMENT = var.environment
      CASE_STATE_TABLE = var.case_state_table_name
      DB_PROXY_ENDPOINT = var.db_proxy_endpoint
      DB_SECRET_ARN = var.db_secret_arn
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }
  tags = { Name = "${var.name_prefix}-policy-evaluation-agent" }
}

resource "aws_lambda_function" "case_summary" {
  function_name = "${var.name_prefix}-case-summary-agent"
  role          = aws_iam_role.lambda.arn
  handler       = "caseSummary.handler"
  runtime       = var.runtime
  filename      = local.agents_zip
  source_code_hash = filebase64sha256(local.agents_zip)
  timeout       = 300
  memory_size   = 1024
  dead_letter_config { target_arn = aws_sqs_queue.agents_dlq.arn }
  tracing_config { mode = "Active" }
  environment {
    variables = {
      ENVIRONMENT = var.environment
      CASE_STATE_TABLE = var.case_state_table_name
      DB_PROXY_ENDPOINT = var.db_proxy_endpoint
      DB_SECRET_ARN = var.db_secret_arn
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }
  tags = { Name = "${var.name_prefix}-case-summary-agent" }
}

resource "aws_lambda_function" "update_case_status" {
  function_name = "${var.name_prefix}-update-case-status"
  role          = aws_iam_role.lambda.arn
  handler       = "updateCaseStatus.handler"
  runtime       = var.runtime
  filename      = local.agents_zip
  source_code_hash = filebase64sha256(local.agents_zip)
  timeout       = 30
  memory_size   = 256
  dead_letter_config { target_arn = aws_sqs_queue.agents_dlq.arn }
  tracing_config { mode = "Active" }
  environment {
    variables = {
      ENVIRONMENT = var.environment
      CASE_STATE_TABLE = var.case_state_table_name
      EVENT_BUS_NAME = var.event_bus_name
      DB_PROXY_ENDPOINT = var.db_proxy_endpoint
      DB_SECRET_ARN = var.db_secret_arn
    }
  }
  tags = { Name = "${var.name_prefix}-update-case-status" }
}

# Data Lifecycle Lambda (P0)
resource "aws_lambda_function" "data_lifecycle" {
  function_name = "${var.name_prefix}-data-lifecycle"
  role          = aws_iam_role.lambda.arn
  handler       = "dataLifecycle.handler"
  runtime       = var.runtime
  filename      = local.agents_zip
  source_code_hash = filebase64sha256(local.agents_zip)
  timeout       = 900 # 15 minutes
  memory_size   = 512
  tracing_config { mode = "Active" }
  environment {
    variables = {
      ENVIRONMENT = var.environment
      DB_PROXY_ENDPOINT = var.db_proxy_endpoint
      DB_SECRET_ARN = var.db_secret_arn
      RETENTION_YEARS = "5"
    }
  }
  tags = { Name = "${var.name_prefix}-data-lifecycle" }
}

