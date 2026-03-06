variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "kms_key_arn" {
  type    = string
  default = null
}
