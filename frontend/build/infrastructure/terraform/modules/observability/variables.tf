variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "api_gateway_id" { type = string; default = "" }
variable "lambda_function_names" { type = list(string); default = [] }
variable "step_function_arn" { type = string; default = "" }
variable "agent_lambda_names" { type = list(string); default = [] }
variable "dlq_queue_names" { type = list(string); default = [] }
variable "monthly_budget_limit" { type = number; default = 2000 }
variable "budget_notification_emails" { type = list(string); default = [] }
