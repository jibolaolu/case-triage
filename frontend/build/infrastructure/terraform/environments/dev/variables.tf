variable "environment" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "FastStart"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "aurora_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "aurora_multi_az" {
  type    = bool
  default = false
}

variable "org_ids" {
  type    = list(string)
  default = ["council-a"]
  description = "Initial organisation IDs for S3 bucket creation"
}

variable "case_types" {
  type    = list(string)
  default = ["hardship-fund"]
}

variable "cognito_user_pool_arn" {
  type        = string
  description = "ARN of Cognito User Pool for API Gateway authorizer"
  default     = ""
}

variable "cognito_user_pool_id" {
  type        = string
  description = "ID of Cognito User Pool (extracted from ARN if needed)"
  default     = ""
}

variable "monthly_budget_limit" {
  type        = number
  description = "Monthly budget limit in USD"
  default     = 2000
}

variable "budget_notification_emails" {
  type        = list(string)
  description = "Email addresses for budget notifications"
  default     = []
}

variable "bedrock_model_id" {
  type    = string
  default = "anthropic.claude-3-sonnet-20240229-v1:0"
}

variable "enable_waf" {
  type    = bool
  default = false
}
