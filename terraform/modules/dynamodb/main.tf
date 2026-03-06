################################################################################
# modules/dynamodb/main.tf  (FIXED)
#
# Fix: attribute blocks expanded to multi-line syntax
#      Terraform does not allow single-line shorthand for nested blocks
#
# case_runtime_state  — hot path; Step Functions polls this for status
# case_audit_trail    — append-only event log; one row per agent status change
################################################################################

variable "prefix" {}

# ─── Table 1: Runtime State ───────────────────────────────────────────────────

resource "aws_dynamodb_table" "case_runtime_state" {
  name         = "${var.prefix}-case-runtime-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "caseId"

  attribute {
    name = "caseId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "orgId"
    type = "S"
  }

  attribute {
    name = "assignedTo"
    type = "S"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "orgId-status-index"
    hash_key        = "orgId"
    range_key       = "status"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "assignedTo-index"
    hash_key        = "assignedTo"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = { Name = "${var.prefix}-case-runtime-state" }
}

# ─── Table 2: Audit Trail ─────────────────────────────────────────────────────
#
# Every agent status transition is appended here.
# Query a full case history:
#   aws dynamodb query \
#     --table-name case-triage-dev-case-audit-trail \
#     --key-condition-expression "caseId = :id" \
#     --expression-attribute-values '{":id": {"S": "MY-CASE-ID"}}' \
#     --region eu-west-2

resource "aws_dynamodb_table" "case_audit_trail" {
  name         = "${var.prefix}-case-audit-trail"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "caseId"
  range_key    = "eventAt"

  attribute {
    name = "caseId"
    type = "S"
  }

  attribute {
    name = "eventAt"
    type = "S"
  }

  attribute {
    name = "agent"
    type = "S"
  }

  global_secondary_index {
    name            = "agent-eventAt-index"
    hash_key        = "agent"
    range_key       = "eventAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = { Name = "${var.prefix}-case-audit-trail" }
}

# ─── Table 3: Notifications ───────────────────────────────────────────────────

resource "aws_dynamodb_table" "notifications" {
  name         = "${var.prefix}-notifications"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "createdAt"

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = { Name = "${var.prefix}-notifications" }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "table_name" {
  value = aws_dynamodb_table.case_runtime_state.name
}

output "table_arn" {
  value = aws_dynamodb_table.case_runtime_state.arn
}

output "audit_trail_table_name" {
  value = aws_dynamodb_table.case_audit_trail.name
}

output "audit_trail_table_arn" {
  value = aws_dynamodb_table.case_audit_trail.arn
}

output "notifications_table_name" {
  value = aws_dynamodb_table.notifications.name
}

output "notifications_table_arn" {
  value = aws_dynamodb_table.notifications.arn
}
