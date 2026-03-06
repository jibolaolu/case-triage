################################################################################
# Aurora Module — PostgreSQL Serverless v2
# Authoritative store for: cases, documents, policy rules, agent outputs
# Uses RDS Data API (no VPC connection needed from Lambda)
# Matches HLD v2 Level 5 data persistence spec
################################################################################

variable "prefix"               {}
variable "environment"          {}
variable "region"               {}
variable "account_id"           {}


# ─── IAM role lookup — avoids circular dependency with IAM module ─────────────
# The IAM module creates this role. We look it up by name here instead of
# accepting it as an input variable, which would create a module cycle.

variable "lambda_exec_role_arn" {
  description = "ARN of the Lambda execution role from IAM module"
  type        = string
}

# ─── Dedicated VPC for Aurora (multi-AZ subnets) ──────────────────────────────
# The default VPC has a single /16 subnet in one AZ, leaving no room for a
# second subnet. A small dedicated VPC avoids that constraint entirely.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "aurora" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.prefix}-aurora-vpc" }
}

resource "aws_subnet" "aurora_a" {
  vpc_id            = aws_vpc.aurora.id
  cidr_block        = "10.0.0.0/25"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "${var.prefix}-aurora-subnet-a" }
}

resource "aws_subnet" "aurora_b" {
  vpc_id            = aws_vpc.aurora.id
  cidr_block        = "10.0.0.128/25"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = { Name = "${var.prefix}-aurora-subnet-b" }
}

resource "aws_db_subnet_group" "aurora" {
  name       = "${var.prefix}-aurora-subnet-group"
  subnet_ids = [aws_subnet.aurora_a.id, aws_subnet.aurora_b.id]

  tags = { Name = "${var.prefix}-aurora-subnet-group" }
}

# ─── Security Group — Aurora (allow RDS Data API + Lambda in same VPC) ────────

resource "aws_security_group" "aurora" {
  name        = "${var.prefix}-aurora-sg"
  description = "Aurora PostgreSQL - RDS Data API access"
  vpc_id      = aws_vpc.aurora.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.aurora.cidr_block]
    description = "PostgreSQL from Aurora VPC"
  }

  tags = { Name = "${var.prefix}-aurora-sg" }
}

# ─── Aurora Serverless v2 Cluster ─────────────────────────────────────────────

resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${var.prefix}-postgres"

  engine         = "aurora-postgresql"
  engine_mode    = "provisioned"   # required for Serverless v2
  engine_version = "16.11"

  database_name   = "case_triage"
  master_username = "ctadmin"

  # Secrets Manager manages the password — no plain text
  manage_master_user_password = true

  serverlessv2_scaling_configuration {
    min_capacity = 0.5   # ~$0.06/hr when idle - scales to 0 on pause
    max_capacity = 8.0   # handles burst load across multiple orgs
  }

  vpc_security_group_ids = [aws_security_group.aurora.id]
  db_subnet_group_name   = aws_db_subnet_group.aurora.name

  # RDS Data API — Lambda calls Aurora via HTTPS, no VPC peering needed
  enable_http_endpoint = true

  # Backups & recovery
  backup_retention_period      = 7
  preferred_backup_window      = "02:00-03:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  # Protection
  deletion_protection = var.environment == "prod" ? true : false
  skip_final_snapshot = var.environment == "prod" ? false : true
  final_snapshot_identifier = var.environment == "prod" ? "${var.prefix}-final-snapshot" : null

  # Encryption
  storage_encrypted = true

  # Point-in-time recovery (PITR) — matches HLD spec
  # Enabled by default with backup_retention_period > 0

  tags = { Name = "${var.prefix}-aurora-cluster" }
}

# ─── Aurora Serverless v2 Instance ────────────────────────────────────────────

resource "aws_rds_cluster_instance" "aurora" {
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"   # Serverless v2 instance type
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  publicly_accessible = false

  performance_insights_enabled = true

  tags = { Name = "${var.prefix}-aurora-instance" }
}

# ─── SSM Parameter Store — store cluster ARN + secret ARN for Lambda env ──────

resource "aws_ssm_parameter" "aurora_cluster_arn" {
  name  = "/${var.prefix}/aurora/cluster-arn"
  type  = "String"
  value = aws_rds_cluster.aurora.arn
}

resource "aws_ssm_parameter" "aurora_secret_arn" {
  name  = "/${var.prefix}/aurora/secret-arn"
  type  = "String"
  value = aws_rds_cluster.aurora.master_user_secret[0].secret_arn
}

resource "aws_ssm_parameter" "aurora_database" {
  name  = "/${var.prefix}/aurora/database"
  type  = "String"
  value = "case_triage"
}

# Schema init is invoked from root main.tf after both Aurora and Lambda modules
# are created, avoiding the dependency ordering issue.

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "cluster_arn"       { value = aws_rds_cluster.aurora.arn }
output "cluster_endpoint"  { value = aws_rds_cluster.aurora.endpoint }
output "secret_arn"        { value = aws_rds_cluster.aurora.master_user_secret[0].secret_arn }
output "database_name"     { value = aws_rds_cluster.aurora.database_name }
output "security_group_id" { value = aws_security_group.aurora.id }
output "aurora_vpc_id" { value = aws_vpc.aurora.id }
