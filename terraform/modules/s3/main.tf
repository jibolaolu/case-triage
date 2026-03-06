################################################################################
# S3 Module — validated-application-intake + audit-logs buckets
################################################################################

variable "prefix"      {}
variable "environment" {}

# ─── Documents Bucket ─────────────────────────────────────────────────────────

resource "aws_s3_bucket" "documents" {
  bucket        = "${var.prefix}-validated-application-intake"
  force_destroy = var.environment != "prod"  # safety guard on prod
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_policy" "documents_https_only" {
  bucket = aws_s3_bucket.documents.id

  depends_on = [aws_s3_bucket_public_access_block.documents]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonHTTPSDirectCalls"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
          # Only deny direct SDK/CLI calls over HTTP — NOT presigned URL calls.
          # Presigned URLs have authType "QueryString"; direct calls use "AuthHeader".
          StringEquals = {
            "aws:authType" = "AuthHeader"
          }
        }
      }
    ]
  })
}
# S3 lifecycle — 7-year retention matching HLD spec
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "document-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""  # ← ADD THIS
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
    transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }
    expiration {
      days = 2555  # 7 years
    }
  }
}

# CORS — allows browser-based direct uploads via presigned URLs
resource "aws_s3_bucket_cors_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["*"]   # Restrict to your portal domain in prod
    expose_headers  = ["ETag"]
    max_age_seconds = 900      # 15 min — matches presigned URL TTL
  }
}

# ─── Audit Logs Bucket ────────────────────────────────────────────────────────

resource "aws_s3_bucket" "audit_logs" {
  bucket        = "${var.prefix}-audit-logs"
  force_destroy = var.environment != "prod"
}

resource "aws_s3_bucket_versioning" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "audit_logs" {
  bucket                  = aws_s3_bucket.audit_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server access logging for documents bucket → audit logs bucket
resource "aws_s3_bucket_logging" "documents" {
  bucket        = aws_s3_bucket.documents.id
  target_bucket = aws_s3_bucket.audit_logs.id
  target_prefix = "s3-access-logs/documents/"
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "documents_bucket_name" { value = aws_s3_bucket.documents.id }
output "documents_bucket_arn"  { value = aws_s3_bucket.documents.arn }
output "audit_bucket_name"     { value = aws_s3_bucket.audit_logs.id }
output "audit_bucket_arn"      { value = aws_s3_bucket.audit_logs.arn }
