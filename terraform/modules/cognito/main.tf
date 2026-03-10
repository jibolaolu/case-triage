################################################################################
# Cognito Module — Authentication for Case Triage System
################################################################################

variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "environment" {
  description = "Environment (e.g., dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "callback_urls" {
  description = "Additional OAuth callback URLs (Cognito does not support wildcards; add your Amplify URL when known)"
  type        = list(string)
  default     = []
}

variable "logout_urls" {
  description = "Additional OAuth logout URLs"
  type        = list(string)
  default     = []
}

# ─── Cognito User Pool ───────────────────────────────────────────────────────

resource "aws_cognito_user_pool" "main" {
  name = "${var.prefix}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days  = 7
  }

  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = false
  }

  schema {
    name                = "custom:role"
    attribute_data_type  = "String"
    required            = false
    mutable             = true
  }

  schema {
    name                = "custom:department"
    attribute_data_type  = "String"
    required            = false
    mutable             = true
  }

  lifecycle {
    ignore_changes = [schema]
  }

  tags = {
    Name        = "${var.prefix}-user-pool"
    Environment = var.environment
  }
}

# ─── User Pool Client (SPA) ───────────────────────────────────────────────────

resource "aws_cognito_user_pool_client" "portal" {
  name         = "${var.prefix}-portal-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  supported_identity_providers = ["COGNITO"]

  callback_urls = concat(
    ["http://localhost:3000/api/auth/callback"],
    var.callback_urls
  )

  logout_urls = concat(
    ["http://localhost:3000"],
    var.logout_urls
  )

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client  = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  prevent_user_existence_errors = "ENABLED"
}

# ─── User Pool Domain (Cognito-hosted) ─────────────────────────────────────────

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.prefix}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

# ─── Cognito Groups ───────────────────────────────────────────────────────────

resource "aws_cognito_user_group" "admin" {
  name         = "ADMIN"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Administrator role with full system access"
  precedence   = 1
}

resource "aws_cognito_user_group" "caseworker" {
  name         = "CASEWORKER"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Caseworker role for triaging and managing cases"
  precedence   = 2
}

resource "aws_cognito_user_group" "manager" {
  name         = "MANAGER"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Manager role for oversight and reporting"
  precedence   = 3
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.arn
}

output "client_id" {
  description = "Client ID of the portal app client"
  value       = aws_cognito_user_pool_client.portal.id
}

output "domain" {
  description = "Cognito domain (prefix only; full URL: https://{domain}.auth.{region}.amazoncognito.com)"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "user_pool_endpoint" {
  description = "OIDC issuer endpoint for the User Pool"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}
