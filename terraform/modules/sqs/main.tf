################################################################################
# SQS Module — Tech Validation Queue + Data Extraction Queue + DLQs
# Also includes EventBridge delivery DLQ
################################################################################

variable "prefix" {}

locals {
  visibility_timeout = 300  # 5 min — matches Lambda max timeout
}

# ─── Tech Validation DLQ ─────────────────────────────────────────────────────

resource "aws_sqs_queue" "tech_validation_dlq" {
  name                      = "${var.prefix}-tech-validation-dlq"
  message_retention_seconds = 1209600  # 14 days
  kms_master_key_id         = "alias/aws/sqs"

  tags = { Name = "${var.prefix}-tech-validation-dlq" }
}

resource "aws_cloudwatch_metric_alarm" "tech_validation_dlq_alarm" {
  alarm_name          = "${var.prefix}-tech-validation-dlq-depth"
  alarm_description   = "Tech validation DLQ has messages — case processing failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  dimensions          = { QueueName = aws_sqs_queue.tech_validation_dlq.name }
}

# ─── Tech Validation Queue ────────────────────────────────────────────────────

resource "aws_sqs_queue" "tech_validation" {
  name                       = "${var.prefix}-tech-validation-queue"
  visibility_timeout_seconds = local.visibility_timeout
  message_retention_seconds  = 86400   # 1 day
  kms_master_key_id          = "alias/aws/sqs"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.tech_validation_dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "${var.prefix}-tech-validation-queue" }
}

# ─── Data Extraction DLQ ─────────────────────────────────────────────────────

resource "aws_sqs_queue" "extraction_dlq" {
  name                      = "${var.prefix}-extraction-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = "alias/aws/sqs"

  tags = { Name = "${var.prefix}-extraction-dlq" }
}

resource "aws_cloudwatch_metric_alarm" "extraction_dlq_alarm" {
  alarm_name          = "${var.prefix}-extraction-dlq-depth"
  alarm_description   = "Extraction DLQ has messages — AI extraction failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  dimensions          = { QueueName = aws_sqs_queue.extraction_dlq.name }
}

# ─── Data Extraction Queue ────────────────────────────────────────────────────

resource "aws_sqs_queue" "extraction" {
  name                       = "${var.prefix}-extraction-queue"
  visibility_timeout_seconds = local.visibility_timeout
  message_retention_seconds  = 86400
  kms_master_key_id          = "alias/aws/sqs"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.extraction_dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "${var.prefix}-extraction-queue" }
}

# ─── EventBridge Delivery DLQ ─────────────────────────────────────────────────

resource "aws_sqs_queue" "eventbridge_dlq" {
  name                      = "${var.prefix}-eventbridge-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = "alias/aws/sqs"

  tags = { Name = "${var.prefix}-eventbridge-dlq" }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "tech_validation_queue_url" { value = aws_sqs_queue.tech_validation.url }
output "tech_validation_queue_arn" { value = aws_sqs_queue.tech_validation.arn }
output "tech_validation_dlq_arn"   { value = aws_sqs_queue.tech_validation_dlq.arn }
output "extraction_queue_url"       { value = aws_sqs_queue.extraction.url }
output "extraction_queue_arn"       { value = aws_sqs_queue.extraction.arn }
output "extraction_dlq_arn"         { value = aws_sqs_queue.extraction_dlq.arn }
output "eventbridge_dlq_arn"        { value = aws_sqs_queue.eventbridge_dlq.arn }

output "all_queue_arns" {
  value = [
    aws_sqs_queue.tech_validation.arn,
    aws_sqs_queue.tech_validation_dlq.arn,
    aws_sqs_queue.extraction.arn,
    aws_sqs_queue.extraction_dlq.arn,
    aws_sqs_queue.eventbridge_dlq.arn,
  ]
}
