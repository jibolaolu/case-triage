variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "lambda_invoke_arn" { type = string }
variable "lambda_function_name" { type = string }
variable "cognito_user_pool_arn" { type = string; default = "" }
variable "enable_waf" { type = bool; default = false }
