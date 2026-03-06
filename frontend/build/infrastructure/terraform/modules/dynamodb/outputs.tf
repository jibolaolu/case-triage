output "case_runtime_state_table_name" {
  value = aws_dynamodb_table.case_runtime_state.name
}
output "idempotency_keys_table_name" {
  value = aws_dynamodb_table.idempotency_keys.name
}
output "event_log_table_name" {
  value = aws_dynamodb_table.event_log.name
}
