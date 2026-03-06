output "policy_bucket" { value = aws_s3_bucket.policy.id }
output "intake_buckets" { value = { for k, b in aws_s3_bucket.intake : k => b.id } }
