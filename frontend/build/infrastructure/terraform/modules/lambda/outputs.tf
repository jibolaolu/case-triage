output "api_lambda_invoke_arn" { value = aws_lambda_function.api.invoke_arn }
output "api_lambda_function_name" { value = aws_lambda_function.api.function_name }
output "finalize_lambda_arn" { value = aws_lambda_function.application_finalize.arn }
output "failure_handler_arn" { value = aws_lambda_function.failure_handler.arn }
output "update_case_status_arn" { value = aws_lambda_function.update_case_status.arn }
output "agent_lambda_arns" = {
  document_validation = aws_lambda_function.document_validation.arn
  data_extraction     = aws_lambda_function.data_extraction.arn
  policy_evaluation   = aws_lambda_function.policy_evaluation.arn
  case_summary        = aws_lambda_function.case_summary.arn
}
output "all_lambda_names" = [
  aws_lambda_function.api.function_name,
  aws_lambda_function.application_init.function_name,
  aws_lambda_function.application_finalize.function_name,
  aws_lambda_function.failure_handler.function_name,
  aws_lambda_function.update_case_status.function_name,
  aws_lambda_function.document_validation.function_name,
  aws_lambda_function.data_extraction.function_name,
  aws_lambda_function.policy_evaluation.function_name,
  aws_lambda_function.case_summary.function_name,
]
output "agent_lambda_names" = [
  aws_lambda_function.document_validation.function_name,
  aws_lambda_function.data_extraction.function_name,
  aws_lambda_function.policy_evaluation.function_name,
  aws_lambda_function.case_summary.function_name,
]
output "api_dlq_name" { value = aws_sqs_queue.api_dlq.name }
output "agents_dlq_name" { value = aws_sqs_queue.agents_dlq.name }
output "data_lifecycle_lambda_arn" { value = aws_lambda_function.data_lifecycle.arn }
