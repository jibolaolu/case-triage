# DynamoDB: case_runtime_state, idempotency_keys

resource "aws_dynamodb_table" "case_runtime_state" {
  name         = "${var.name_prefix}-case-runtime-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "case_id"

  attribute {
    name = "case_id"
    type = "S"
  }
  attribute {
    name = "org_id"
    type = "S"
  }
  attribute {
    name = "status"
    type = "S"
  }
  attribute {
    name = "updated_at"
    type = "S"
  }

  global_secondary_index {
    name            = "org-status-index"
    hash_key        = "org_id"
    range_key       = "status"
    projection_type = "ALL"
  }
  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    range_key       = "updated_at"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  server_side_encryption { enabled = true }
  point_in_time_recovery { enabled = true }

  tags = {
    Name = "${var.name_prefix}-case-runtime-state"
  }
}

resource "aws_dynamodb_table" "idempotency_keys" {
  name         = "${var.name_prefix}-idempotency-keys"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "idempotency_key"

  attribute {
    name = "idempotency_key"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  server_side_encryption { enabled = true }
  point_in_time_recovery { enabled = true }

  tags = {
    Name = "${var.name_prefix}-idempotency-keys"
  }
}

# Event log for replay: CASE_INTAKE_VALIDATED, CASE_AI_FAILED, CASE_DECISION_RECORDED
resource "aws_dynamodb_table" "event_log" {
  name         = "${var.name_prefix}-event-log"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }
  attribute {
    name = "event_type"
    type = "S"
  }
  attribute {
    name = "case_id"
    type = "S"
  }
  attribute {
    name = "timestamp"
    type = "S"
  }

  global_secondary_index {
    name            = "event-type-timestamp-index"
    hash_key        = "event_type"
    range_key       = "timestamp"
    projection_type = "ALL"
  }
  global_secondary_index {
    name            = "case-id-timestamp-index"
    hash_key        = "case_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  server_side_encryption { enabled = true }
  point_in_time_recovery { enabled = true }

  tags = {
    Name = "${var.name_prefix}-event-log"
  }
}
