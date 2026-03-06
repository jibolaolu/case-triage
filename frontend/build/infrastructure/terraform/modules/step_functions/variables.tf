variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "lambda_arns" {
  type = object({
    document_validation = string
    data_extraction     = string
    policy_evaluation   = string
    case_summary        = string
  })
}
variable "failure_handler_arn" { type = string }
variable "update_case_status_arn" { type = string }
