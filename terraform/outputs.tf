################################################################################
# outputs.tf  (UPDATED)
################################################################################

output "api_gateway_url" {
  value = module.api_gateway.base_url
}

output "api_gateway_init_endpoint" {
  value = "${module.api_gateway.base_url}/applications/init"
}

output "api_gateway_complete_endpoint" {
  value = "${module.api_gateway.base_url}/applications/complete"
}

output "documents_bucket_name" {
  value = module.s3.documents_bucket_name
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "audit_trail_table_name" {
  description = "NEW: DynamoDB audit trail — query to track all agent activity"
  value       = module.dynamodb.audit_trail_table_name
}

output "aurora_cluster_arn" {
  description = "NEW: Aurora cluster ARN — needed for RDS Data API calls"
  value       = module.aurora.cluster_arn
}

output "aurora_endpoint" {
  description = "NEW: Aurora cluster endpoint"
  value       = module.aurora.cluster_endpoint
}

output "aurora_secret_arn" {
  description = "NEW: Secrets Manager ARN holding Aurora credentials"
  value       = module.aurora.secret_arn
  sensitive   = true
}

output "schema_init_function_name" {
  description = "NEW: Invoke this once after apply to create Aurora tables"
  value       = module.lambda.schema_init_function_name
}

output "eventbridge_bus_name" {
  value = module.eventbridge.bus_name
}

output "step_functions_arn" {
  value = module.step_functions.state_machine_arn
}

output "tech_validation_queue_url" {
  value = module.sqs.tech_validation_queue_url
}

output "extraction_queue_url" {
  value = module.sqs.extraction_queue_url
}

output "amplify_app_url" {
  description = "Amplify portal URL (empty when no GitHub token provided)"
  value       = length(module.amplify) > 0 ? module.amplify[0].default_domain : ""
}

output "amplify_app_id" {
  description = "Amplify app ID (empty when no GitHub token provided)"
  value       = length(module.amplify) > 0 ? module.amplify[0].app_id : ""
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID for authentication"
  value       = module.cognito.user_pool_id
}

output "cognito_client_id" {
  description = "Cognito app client ID for the portal"
  value       = module.cognito.client_id
}
