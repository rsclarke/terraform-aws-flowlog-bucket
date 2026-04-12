output "bucket_name" {
  description = "Full name of the S3 bucket (including account-regional suffix)"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.this.arn
}

output "kms_key_arn" {
  description = "Effective KMS key ARN when use_kms is true, otherwise null"
  value       = local.effective_kms_key_arn
}

output "read_policy_arn" {
  description = "ARN of the IAM policy granting read access to flow logs"
  value       = aws_iam_policy.read.arn
}

output "flow_logs_destination_arn" {
  description = "Bucket ARN for use as log_destination in aws_flow_log resources"
  value       = aws_s3_bucket.this.arn
}
