# EventBridge: CASE_INTAKE_VALIDATED -> SQS -> Lambda -> Step Functions
# DLQ for EventBridge target failures

resource "aws_sqs_queue" "intake_events" {
  name                      = "${var.name_prefix}-intake-events"
  message_retention_seconds = 1209600 # 14 days
  receive_wait_time_seconds = 20
  tags                      = { Name = "${var.name_prefix}-intake-events" }
}

resource "aws_sqs_queue" "intake_consumer_dlq" {
  name                      = "${var.name_prefix}-intake-consumer-dlq"
  message_retention_seconds = 1209600
  tags                      = { Name = "${var.name_prefix}-intake-consumer-dlq" }
}

resource "aws_sqs_queue_redrive_policy" "intake_events" {
  queue_url = aws_sqs_queue.intake_events.id
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.intake_consumer_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "eventbridge_target_dlq" {
  name                      = "${var.name_prefix}-eventbridge-target-dlq"
  message_retention_seconds = 1209600
  tags                      = { Name = "${var.name_prefix}-eventbridge-target-dlq" }
}

resource "aws_sqs_queue_policy" "intake_events" {
  queue_url = aws_sqs_queue.intake_events.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.intake_events.arn
    }]
  })
}

resource "aws_sqs_queue_policy" "eventbridge_target_dlq" {
  queue_url = aws_sqs_queue.eventbridge_target_dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.eventbridge_target_dlq.arn
    }]
  })
}

# EventBridge rule: CASE_INTAKE_VALIDATED -> SQS
resource "aws_cloudwatch_event_rule" "intake_validated" {
  name        = "${var.name_prefix}-intake-validated"
  description = "Route CASE_INTAKE_VALIDATED to SQS"
  event_pattern = jsonencode({
    source      = ["case.intake"]
    detail-type = ["CASE_INTAKE_VALIDATED"]
  })
  tags = { Name = "${var.name_prefix}-intake-validated" }
}

resource "aws_iam_role" "eventbridge_sfn" {
  name = "${var.name_prefix}-eventbridge-sfn"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_sqs" {
  name   = "${var.name_prefix}-eventbridge-sqs"
  role   = aws_iam_role.eventbridge_sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.intake_events.arn
    }]
  })
}

resource "aws_cloudwatch_event_target" "intake_sqs" {
  rule      = aws_cloudwatch_event_rule.intake_validated.name
  target_id = "IntakeSQSTarget"
  arn       = aws_sqs_queue.intake_events.arn
  role_arn  = aws_iam_role.eventbridge_sfn.arn
  retry_policy {
    maximum_retry_attempts = 3
    maximum_event_age_in_seconds = 3600
  }
  dead_letter_config {
    arn = aws_sqs_queue.eventbridge_target_dlq.arn
  }
}

# Intake processor Lambda (bridges SQS -> Step Functions)
data "archive_file" "intake_processor_placeholder" {
  type        = "zip"
  output_path = "${path.module}/intake_processor_placeholder.zip"
  source {
    content  = "placeholder"
    filename = "placeholder.txt"
  }
}

resource "aws_iam_role" "intake_processor" {
  name = "${var.name_prefix}-intake-processor-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "intake_processor_basic" {
  role       = aws_iam_role.intake_processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "intake_processor_xray" {
  role       = aws_iam_role.intake_processor.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "intake_processor_sfn" {
  name   = "${var.name_prefix}-intake-processor-sfn"
  role   = aws_iam_role.intake_processor.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = var.step_function_arn
    }]
  })
}

resource "aws_lambda_function" "intake_processor" {
  function_name = "${var.name_prefix}-intake-processor"
  role          = aws_iam_role.intake_processor.arn
  handler       = "intakeProcessor.handler"
  runtime       = var.runtime
  filename      = data.archive_file.intake_processor_placeholder.output_path
  source_code_hash = filebase64sha256(data.archive_file.intake_processor_placeholder.output_path)
  timeout       = 60
  memory_size   = 256
  dead_letter_config { target_arn = aws_sqs_queue.intake_consumer_dlq.arn }
  tracing_config { mode = "Active" }
  environment {
    variables = {
      STEP_FUNCTION_ARN = var.step_function_arn
      ENVIRONMENT       = var.environment
    }
  }
  tags = { Name = "${var.name_prefix}-intake-processor" }
}

resource "aws_lambda_event_source_mapping" "intake_processor" {
  event_source_arn = aws_sqs_queue.intake_events.arn
  function_name    = aws_lambda_function.intake_processor.arn
  batch_size       = 10
  enabled          = true
}

# Data Lifecycle Schedule (P0) - Daily at 2 AM UTC
resource "aws_cloudwatch_event_rule" "data_lifecycle_schedule" {
  name                = "${var.name_prefix}-data-lifecycle-schedule"
  description         = "Trigger data lifecycle cleanup daily"
  schedule_expression = "cron(0 2 * * ? *)" # Daily at 2 AM UTC
  tags                = { Name = "${var.name_prefix}-data-lifecycle-schedule" }
}

resource "aws_cloudwatch_event_target" "data_lifecycle" {
  count     = var.data_lifecycle_lambda_arn != "" ? 1 : 0
  rule      = aws_cloudwatch_event_rule.data_lifecycle_schedule.name
  target_id = "DataLifecycleLambda"
  arn       = var.data_lifecycle_lambda_arn
}

resource "aws_lambda_permission" "data_lifecycle" {
  count         = var.data_lifecycle_lambda_arn != "" ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.data_lifecycle_lambda_arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.data_lifecycle_schedule.arn
}

output "intake_queue_arn" { value = aws_sqs_queue.intake_events.arn }
output "intake_queue_url" { value = aws_sqs_queue.intake_events.url }
output "intake_consumer_dlq_arn" { value = aws_sqs_queue.intake_consumer_dlq.arn }
output "eventbridge_target_dlq_arn" { value = aws_sqs_queue.eventbridge_target_dlq.arn }
output "intake_consumer_dlq_name" { value = aws_sqs_queue.intake_consumer_dlq.name }
output "eventbridge_target_dlq_name" { value = aws_sqs_queue.eventbridge_target_dlq.name }
