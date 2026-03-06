################################################################################
# Variables — Case Triage Management System
################################################################################

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-2" # London — appropriate for UK public sector
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Short project identifier used in all resource names"
  type        = string
  default     = "case-triage"
}

variable "github_access_token" {
  description = "GitHub personal access token for Amplify to access the repository"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ses_sender_email" {
  description = "Verified SES sender email address"
  type        = string
  default     = "noreply@example.com"
}
