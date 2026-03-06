output "kms_key_id" { value = aws_kms_key.main.id }
output "kms_key_arn" { value = aws_kms_key.main.arn }
output "lambda_sg_id" { value = aws_security_group.lambda.id }
output "aurora_sg_id" { value = aws_security_group.aurora.id }
output "rds_proxy_sg_id" { value = aws_security_group.rds_proxy.id }
