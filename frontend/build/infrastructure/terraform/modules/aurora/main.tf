# Minimal Aurora PostgreSQL + RDS Proxy for FastStart
# For dev, single instance; for prd use multi_az and larger instance_class

data "aws_caller_identity" "current" {}

resource "random_password" "db" {
  length  = 32
  special = true
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-aurora-subnet"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${var.name_prefix}-aurora-subnet" }
}

resource "aws_rds_cluster" "main" {
  cluster_identifier     = "${var.name_prefix}-cluster"
  engine                 = "aurora-postgresql"
  engine_mode            = "provisioned"
  database_name          = "faststart"
  master_username        = "faststart_admin"
  master_password        = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.aurora_security_group_id]
  storage_encrypted      = true
  kms_key_id             = var.kms_key_id
  skip_final_snapshot    = var.environment != "prd"
  tags                   = { Name = "${var.name_prefix}-cluster" }
}

resource "aws_rds_cluster_instance" "main" {
  count              = var.multi_az ? 2 : 1
  identifier         = "${var.name_prefix}-instance-${count.index}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.main.engine
  tags               = { Name = "${var.name_prefix}-instance-${count.index}" }
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name_prefix}-db-credentials"
  recovery_window_in_days = 7
  tags                    = { Name = "${var.name_prefix}-db-secret" }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = aws_rds_cluster.main.master_username
    password = random_password.db.result
    host     = aws_rds_cluster.main.endpoint
    port     = 5432
    dbname   = aws_rds_cluster.main.database_name
  })
}

resource "aws_db_proxy" "main" {
  name                   = "${var.name_prefix}-proxy"
  engine_family          = "POSTGRESQL"
  auth {
    auth_scheme = "SECRETS"
    secret_arn = aws_secretsmanager_secret.db.arn
  }
  role_arn               = aws_iam_role.proxy.arn
  vpc_subnet_ids         = var.private_subnet_ids
  vpc_security_group_ids = [var.rds_proxy_security_group_id]
  require_tls            = true
  tags                   = { Name = "${var.name_prefix}-proxy" }
}

resource "aws_db_proxy_default_target_group" "main" {
  db_proxy_name = aws_db_proxy.main.name
}

resource "aws_db_proxy_target" "main" {
  db_proxy_name         = aws_db_proxy.main.name
  target_group_name     = aws_db_proxy_default_target_group.main.name
  db_cluster_identifier = aws_rds_cluster.main.id
}

resource "aws_iam_role" "proxy" {
  name = "${var.name_prefix}-rds-proxy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = { Service = "rds.amazonaws.com" }
      Effect = "Allow"
    }]
  })
}

resource "aws_iam_role_policy" "proxy" {
  name   = "${var.name_prefix}-rds-proxy-secrets"
  role   = aws_iam_role.proxy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.db.arn]
    }]
  })
}
