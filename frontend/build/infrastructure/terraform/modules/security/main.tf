# KMS key for encryption; security groups for Lambda, Aurora, RDS Proxy

resource "aws_kms_key" "main" {
  description             = "FastStart ${var.environment} encryption key"
  deletion_window_in_days = 10
  tags                    = { Name = "${var.name_prefix}-kms" }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.name_prefix}-key"
  target_key_id = aws_kms_key.main.key_id
}

resource "aws_security_group" "lambda" {
  name_prefix = "${var.name_prefix}-lambda-"
  vpc_id      = var.vpc_id
  description = "Lambda for FastStart"
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.name_prefix}-lambda-sg" }
}

resource "aws_security_group" "aurora" {
  name_prefix = "${var.name_prefix}-aurora-"
  vpc_id      = var.vpc_id
  description = "Aurora PostgreSQL"
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
  tags = { Name = "${var.name_prefix}-aurora-sg" }
}

resource "aws_security_group" "rds_proxy" {
  name_prefix = "${var.name_prefix}-rds-proxy-"
  vpc_id      = var.vpc_id
  description = "RDS Proxy"
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.aurora.id]
  }
  tags = { Name = "${var.name_prefix}-rds-proxy-sg" }
}
