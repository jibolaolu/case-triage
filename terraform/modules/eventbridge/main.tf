################################################################################
# EventBridge Module — Custom bus + rule → Step Functions
################################################################################

variable "prefix"               {}
variable "step_functions_arn"   {}
variable "eventbridge_role_arn" {}
variable "eventbridge_dlq_arn"  {}

# ─── Custom Event Bus ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_event_bus" "case_triage" {
  name = "${var.prefix}-case-triage-bus"
}

# 30-day archive for replay capability (matches HLD)
resource "aws_cloudwatch_event_archive" "case_triage" {
  name             = "${var.prefix}-event-archive"
  event_source_arn = aws_cloudwatch_event_bus.case_triage.arn
  retention_days   = 30
}

# ─── Rule: CASE_INTAKE_VALIDATED → Step Functions ─────────────────────────────

resource "aws_cloudwatch_event_rule" "intake_validated" {
  name           = "${var.prefix}-intake-validated-rule"
  description    = "Routes CASE_INTAKE_VALIDATED events to the AI orchestration state machine"
  event_bus_name = aws_cloudwatch_event_bus.case_triage.name

  event_pattern = jsonencode({
    source      = ["case.intake"]
    detail-type = ["CASE_INTAKE_VALIDATED"]
  })
}

# ─── Rule: CASE_DECISION_RECORDED / CASE_ESCALATED (for future notification Lambda) ───

resource "aws_cloudwatch_event_rule" "case_decision" {
  name           = "${var.prefix}-case-decision-rule"
  event_bus_name = aws_cloudwatch_event_bus.case_triage.name
  event_pattern = jsonencode({
    source      = ["case.triage"]
    detail-type = ["CASE_DECISION_RECORDED", "CASE_ESCALATED"]
  })
}

resource "aws_cloudwatch_event_target" "step_functions" {
  rule           = aws_cloudwatch_event_rule.intake_validated.name
  event_bus_name = aws_cloudwatch_event_bus.case_triage.name
  target_id      = "StartStepFunctions"
  arn            = var.step_functions_arn
  role_arn       = var.eventbridge_role_arn

  # Dead-letter queue — captures failed Step Functions trigger deliveries
  dead_letter_config {
    arn = var.eventbridge_dlq_arn
  }

  # Retry policy — up to 24 hours of retries before DLQ
  retry_policy {
    maximum_event_age_in_seconds = 86400
    maximum_retry_attempts       = 185
  }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "bus_name" { value = aws_cloudwatch_event_bus.case_triage.name }
output "bus_arn"  { value = aws_cloudwatch_event_bus.case_triage.arn }
