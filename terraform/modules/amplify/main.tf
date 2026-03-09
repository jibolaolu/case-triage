################################################################################
# Amplify Module — Next.js 14 Caseworker Portal (SSR via WEB_COMPUTE)
################################################################################

variable "prefix"      {}
variable "environment" {}
variable "region"      {}

variable "github_repository" {
  description = "GitHub repository URL (HTTPS)"
  type        = string
}

variable "github_branch" {
  description = "Git branch to deploy from"
  type        = string
}

variable "github_access_token" {
  description = "GitHub personal access token (classic, with repo + admin:repo_hook scopes)"
  type        = string
  sensitive   = true
}

variable "api_gateway_url" {
  description = "Base URL of the API Gateway (passed as env var to the frontend)"
  type        = string
  default     = ""
}

variable "cognito_user_pool_id" { default = "" }
variable "cognito_client_id"    { default = "" }

# ─── IAM Role for Amplify ─────────────────────────────────────────────────────

resource "aws_iam_role" "amplify" {
  name = "${var.prefix}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "amplify.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.prefix}-amplify-role" }
}

resource "aws_iam_role_policy_attachment" "amplify_admin" {
  role       = aws_iam_role.amplify.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess-Amplify"
}

# ─── Amplify App ──────────────────────────────────────────────────────────────

resource "aws_amplify_app" "portal" {
  name       = "${var.prefix}-portal"
  repository = var.github_repository
  platform   = "WEB_COMPUTE"

  access_token         = var.github_access_token
  iam_service_role_arn = aws_iam_role.amplify.arn

  build_spec = <<-YAML
    version: 1
    applications:
      - appRoot: frontend/build/ui
        frontend:
          phases:
            preBuild:
              commands:
                - npm install --legacy-peer-deps
            build:
              commands:
                - env | grep -e NEXT_PUBLIC_ >> .env.production || true
                - npm run build
          artifacts:
            baseDirectory: .next
            files:
              - '**/*'
          cache:
            paths:
              - .next/cache/**/*
              - node_modules/**/*
  YAML

  environment_variables = {
    NEXT_PUBLIC_API_URL       = var.api_gateway_url
    NEXT_PUBLIC_ENVIRONMENT   = var.environment
    AMPLIFY_MONOREPO_APP_ROOT = "frontend/build/ui"
    NEXT_PUBLIC_COGNITO_USER_POOL_ID = var.cognito_user_pool_id
    NEXT_PUBLIC_COGNITO_CLIENT_ID    = var.cognito_client_id
  }

  tags = { Name = "${var.prefix}-portal" }
}

# ─── Branch ───────────────────────────────────────────────────────────────────

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.portal.id
  branch_name = var.github_branch

  framework         = "Next.js - SSR"
  stage             = var.environment == "prod" ? "PRODUCTION" : "DEVELOPMENT"
  enable_auto_build = true

  environment_variables = {
    NEXT_PUBLIC_ENVIRONMENT = var.environment
  }

  tags = { Branch = var.github_branch }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "app_id" {
  value = aws_amplify_app.portal.id
}

output "default_domain" {
  description = "Amplify default domain (https://<branch>.<app-id>.amplifyapp.com)"
  value       = "https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.portal.default_domain}"
}

output "app_arn" {
  value = aws_amplify_app.portal.arn
}
