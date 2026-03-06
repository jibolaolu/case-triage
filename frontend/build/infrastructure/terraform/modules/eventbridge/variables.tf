variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "step_function_arn" { type = string }
variable "runtime" { type = string; default = "nodejs20.x" }
variable "data_lifecycle_lambda_arn" { type = string; default = "" }
