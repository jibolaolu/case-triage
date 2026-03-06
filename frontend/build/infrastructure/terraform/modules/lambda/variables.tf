variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "vpc_config" { type = object({ subnet_ids = list(string), security_group_ids = list(string) }) }
variable "runtime" { type = string }
variable "case_state_table_name" { type = string }
variable "idempotency_table_name" { type = string }
variable "db_proxy_endpoint" { type = string }
variable "db_secret_arn" { type = string }
variable "event_bus_name" { type = string }
variable "bedrock_model_id" { type = string }
variable "api_source_path" { type = string }
variable "agents_source_path" { type = string }
variable "event_log_table_name" { type = string; default = "" }
variable "cognito_user_pool_id" { type = string; default = "" }
