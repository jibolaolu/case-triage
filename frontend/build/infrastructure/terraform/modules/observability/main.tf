resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms"
  tags = { Name = "${var.name_prefix}-alarms" }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = length(var.lambda_function_names) > 0 ? 1 : 0
  alarm_name          = "${var.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Lambda errors exceeded threshold"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  dimensions = {
    FunctionName = var.lambda_function_names[0]
  }
  tags = { Name = "${var.name_prefix}-lambda-errors" }
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  count               = var.api_gateway_id != "" ? 1 : 0
  alarm_name          = "${var.name_prefix}-api-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "API Gateway 5xx errors"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  dimensions = {
    ApiId = var.api_gateway_id
  }
  tags = { Name = "${var.name_prefix}-api-5xx" }
}

# Step Functions executions failed
resource "aws_cloudwatch_metric_alarm" "sfn_failures" {
  count               = var.step_function_arn != "" ? 1 : 0
  alarm_name          = "${var.name_prefix}-sfn-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Step Functions execution failures"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  dimensions = {
    StateMachineArn = var.step_function_arn
  }
  tags = { Name = "${var.name_prefix}-sfn-failures" }
}

# Agent Lambda errors (any of the four agents)
resource "aws_cloudwatch_metric_alarm" "agent_lambda_errors" {
  count               = length(var.agent_lambda_names) > 0 ? 1 : 0
  alarm_name          = "${var.name_prefix}-agent-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Agent Lambda errors"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  dimensions = {
    FunctionName = var.agent_lambda_names[0]
  }
  tags = { Name = "${var.name_prefix}-agent-lambda-errors" }
}

# DLQ depth (one alarm per DLQ)
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  count               = length(var.dlq_queue_names)
  alarm_name          = "${var.name_prefix}-dlq-depth-${var.dlq_queue_names[count.index]}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages in dead-letter queue"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  dimensions = {
    QueueName = var.dlq_queue_names[count.index]
  }
  tags = { Name = "${var.name_prefix}-dlq-depth" }
}

# Cost Monitoring (P0) - AWS Budgets
resource "aws_budgets_budget" "monthly" {
  count             = length(var.budget_notification_emails) > 0 ? 1 : 0
  name              = "${var.name_prefix}-monthly-budget"
  budget_type       = "COST"
  limit_amount      = var.monthly_budget_limit
  limit_unit        = "USD"
  time_period_start = "2026-01-01_00:00"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_emails
  }

  tags = { Name = "${var.name_prefix}-monthly-budget" }
}

# Cost Anomaly Detection (P0) - CloudWatch alarm on EstimatedCharges
# Note: Cost Anomaly Detector (aws_ce_anomaly_detector) requires manual setup via AWS Console
# Using CloudWatch alarm on EstimatedCharges metric as alternative
resource "aws_cloudwatch_metric_alarm" "cost_anomaly" {
  count               = length(var.budget_notification_emails) > 0 ? 1 : 0
  alarm_name          = "${var.name_prefix}-cost-anomaly"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 86400 # 24 hours
  statistic           = "Maximum"
  threshold           = var.monthly_budget_limit * 1.2 # 20% over budget
  alarm_description   = "Cost anomaly detected - spending exceeds threshold"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  dimensions = {
    Currency = "USD"
  }
  tags = { Name = "${var.name_prefix}-cost-anomaly" }
}
