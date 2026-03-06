# Policy bucket; optional intake buckets per org/case-type (create via for_each)

resource "aws_s3_bucket" "policy" {
  bucket = "${var.name_prefix}-policy-definitions"
  tags   = { Name = "${var.name_prefix}-policy-definitions" }
}

resource "aws_s3_bucket_versioning" "policy" {
  bucket = aws_s3_bucket.policy.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "policy" {
  bucket = aws_s3_bucket.policy.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "policy" {
  bucket                  = aws_s3_bucket.policy.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for policy bucket (P0)
resource "aws_s3_bucket_lifecycle_configuration" "policy" {
  bucket = aws_s3_bucket.policy.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "delete-old-versions"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# Intake buckets: one per org + case_type (naming: <org-id>-<case-type>-applicant-intake-s3-<env>)
resource "aws_s3_bucket" "intake" {
  for_each = toset([for o in var.org_ids : for c in var.case_types : "${o}-${c}"])
  bucket   = "${each.key}-applicant-intake-s3-${var.environment}"
  tags     = { Name = "${var.name_prefix}-intake-${each.key}", OrganisationId = split("-", each.key)[0] }
}

resource "aws_s3_bucket_versioning" "intake" {
  for_each = aws_s3_bucket.intake
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "intake" {
  for_each = aws_s3_bucket.intake
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "intake" {
  for_each                = aws_s3_bucket.intake
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for intake buckets (P0) - aligns with case retention (5 years)
resource "aws_s3_bucket_lifecycle_configuration" "intake" {
  for_each = aws_s3_bucket.intake
  bucket   = each.value.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "delete-after-retention"
    status = "Enabled"
    expiration {
      days = 1825 # 5 years (aligned with case retention)
    }
  }

  rule {
    id     = "delete-old-versions"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}
