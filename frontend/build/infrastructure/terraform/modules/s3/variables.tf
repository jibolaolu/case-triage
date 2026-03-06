variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "org_ids" { type = list(string) }
variable "case_types" { type = list(string) }
variable "kms_key_arn" { type = string }
