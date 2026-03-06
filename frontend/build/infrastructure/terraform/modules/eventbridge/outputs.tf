output "intake_queue_arn" {
  value = aws_sqs_queue.intake_events.arn
}
output "intake_queue_url" {
  value = aws_sqs_queue.intake_events.url
}
output "intake_consumer_dlq_arn" {
  value = aws_sqs_queue.intake_consumer_dlq.arn
}
output "eventbridge_target_dlq_arn" {
  value = aws_sqs_queue.eventbridge_target_dlq.arn
}
output "intake_consumer_dlq_name" { value = aws_sqs_queue.intake_consumer_dlq.name }
output "eventbridge_target_dlq_name" { value = aws_sqs_queue.eventbridge_target_dlq.name }
