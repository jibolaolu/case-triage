################################################################################
# modules/iam/main.tf  (UPDATED)
#
# CHANGES:
#   + DynamoDBAuditTrail      — PutItem/Query on new audit trail table
#   + AuroraRDSDataAPI        — execute_statement on Aurora cluster
#   + SecretsManagerAurora    — read Aurora credentials from Secrets Manager
#   + Step Functions role gets audit trail read access for observability
################################################################################

variable "prefix"                  {}
variable "account_id"              {}
variable "region"                  {}
variable "s3_bucket_arn"           {}
variable "dynamodb_table_arn"      {}
variable "audit_trail_table_arn"   {}
variable "sqs_queue_arns"          { type = list(string) }
variable "eventbridge_bus_arn"     {}
variable "step_functions_arn"      { default = "" }
variable "aurora_cluster_arn"      { default = "" }
variable "aurora_secret_arn"       { default = "" }
variable "notifications_table_arn" { default = "" }
variable "cognito_user_pool_arn"   { default = "" }

# ─── Lambda Execution Role ────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_exec" {
  name = "${var.prefix}-lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name = "${var.prefix}-lambda-permissions"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([

      # CloudWatch Logs
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${var.prefix}-*"
      },

      # S3 — documents bucket
      {
        Sid    = "S3DocumentsAccess"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket", "s3:HeadObject",
                  "s3:GetObjectVersion", "s3:GetBucketLocation"]
        Resource = [var.s3_bucket_arn, "${var.s3_bucket_arn}/*"]
      },

      # DynamoDB — runtime state table
      {
        Sid    = "DynamoDBRuntimeState"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:PutItem",
                  "dynamodb:UpdateItem", "dynamodb:Query"]
        Resource = [var.dynamodb_table_arn,
                    "${var.dynamodb_table_arn}/index/*"]
      },

      # DynamoDB — audit trail
      {
        Sid    = "DynamoDBAuditTrail"
        Effect = "Allow"
        Action = ["dynamodb:PutItem", "dynamodb:Query", "dynamodb:GetItem"]
        Resource = [var.audit_trail_table_arn,
                    "${var.audit_trail_table_arn}/index/*"]
      },

      # SES — send email
      {
        Sid    = "SESSendEmail"
        Effect = "Allow"
        Action = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },

      # Aurora RDS Data API
      {
        Sid    = "AuroraRDSDataAPI"
        Effect = "Allow"
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement",
          "rds-data:BeginTransaction",
          "rds-data:CommitTransaction",
          "rds-data:RollbackTransaction"
        ]
        Resource = var.aurora_cluster_arn != "" ? [var.aurora_cluster_arn] : [
          "arn:aws:rds:${var.region}:${var.account_id}:cluster:${var.prefix}-postgres"
        ]
      },

      # Secrets Manager — Aurora credentials (FIXED: covers both named + RDS-managed secrets)
      {
        Sid    = "SecretsManagerAurora"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.prefix}/*",
          "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:rds!cluster-*"
        ]
      },

      # SQS — all queues
      {
        Sid    = "SQSAccess"
        Effect = "Allow"
        Action = ["sqs:SendMessage", "sqs:ReceiveMessage",
                  "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = var.sqs_queue_arns
      },

      # EventBridge
      {
        Sid      = "EventBridgePut"
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = var.eventbridge_bus_arn
      },

      # Textract — OCR
      {
        Sid    = "TextractOCR"
        Effect = "Allow"
        Action = ["textract:DetectDocumentText", "textract:AnalyzeDocument"]
        Resource = "*"
      },

      # Bedrock — Claude inference
      {
        Sid    = "BedrockInvokeModel"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "*"
      },

      # AWS Marketplace — Anthropic model subscription
      {
        Sid    = "MarketplaceAnthropicSubscription"
        Effect = "Allow"
        Action = ["aws-marketplace:ViewSubscriptions",
                  "aws-marketplace:Subscribe",
                  "aws-marketplace:Unsubscribe"]
        Resource = "*"
      },

      # X-Ray
      {
        Sid    = "XRayTracing"
        Effect = "Allow"
        Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ],
    # Conditional: Notifications DynamoDB (only when ARN provided)
    var.notifications_table_arn != "" ? [{
      Sid    = "DynamoDBNotifications"
      Effect = "Allow"
      Action = ["dynamodb:GetItem", "dynamodb:PutItem",
                "dynamodb:UpdateItem", "dynamodb:Query", "dynamodb:DeleteItem"]
      Resource = [var.notifications_table_arn,
                  "${var.notifications_table_arn}/index/*"]
    }] : [],
    # Conditional: Cognito admin (only when ARN provided)
    var.cognito_user_pool_arn != "" ? [{
      Sid    = "CognitoAdmin"
      Effect = "Allow"
      Action = [
        "cognito-idp:AdminCreateUser",
        "cognito-idp:AdminDeleteUser",
        "cognito-idp:AdminEnableUser",
        "cognito-idp:AdminDisableUser",
        "cognito-idp:AdminAddUserToGroup",
        "cognito-idp:AdminRemoveUserFromGroup",
        "cognito-idp:AdminListGroupsForUser",
        "cognito-idp:ListUsers"
      ]
      Resource = [var.cognito_user_pool_arn]
    }] : []
    )
  })
}

# ─── Step Functions Role ──────────────────────────────────────────────────────

resource "aws_iam_role" "step_functions" {
  name = "${var.prefix}-sfn-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "step_functions_permissions" {
  name = "${var.prefix}-sfn-permissions"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      {
        Sid      = "InvokeLambda"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:${var.region}:${var.account_id}:function:${var.prefix}-*"
      },
      {
        Sid      = "SQSSend"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = var.sqs_queue_arns
      },
      # Step Functions polls DynamoDB directly (native SDK integration)
      {
        Sid    = "DynamoDBPollCaseStatus"
        Effect = "Allow"
        Action = ["dynamodb:GetItem"]
        Resource = [var.dynamodb_table_arn,
                    "${var.dynamodb_table_arn}/index/*"]
      },
      {
        Sid    = "XRayTracing"
        Effect = "Allow"
        Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords",
                  "xray:GetSamplingRules", "xray:GetSamplingTargets"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogDelivery", "logs:GetLogDelivery",
                  "logs:UpdateLogDelivery", "logs:DeleteLogDelivery",
                  "logs:ListLogDeliveries", "logs:PutResourcePolicy",
                  "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
        Resource = "*"
      }
    ]
  })
}

# ─── EventBridge Role ─────────────────────────────────────────────────────────

resource "aws_iam_role" "eventbridge" {
  name = "${var.prefix}-eventbridge-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_permissions" {
  name = "${var.prefix}-eventbridge-permissions"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "StartStepFunctions"
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = var.step_functions_arn != "" ? var.step_functions_arn : "*"
    }]
  })
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "lambda_exec_role_arn"    { value = aws_iam_role.lambda_exec.arn }
output "step_functions_role_arn" { value = aws_iam_role.step_functions.arn }
output "eventbridge_role_arn"    { value = aws_iam_role.eventbridge.arn }
