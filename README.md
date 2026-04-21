# terraform-aws-flowlog-bucket

Reusable Terraform module that provisions an S3 bucket for centralised VPC Flow Log retention with:

- S3 account-regional namespace to prevent bucketsquatting
- SSE-S3 by default, with optional SSE-KMS mode
- Bucket versioning and public access blocking
- Bucket policy allowing `delivery.logs.amazonaws.com` scoped to your AWS Organisation
- Default lifecycle tiers (Standard → Glacier → Deep Archive → expire at 7 years)
- IAM read policy for consuming flow logs

The bucket is always created in your account's [account-regional namespace](https://aws.amazon.com/blogs/aws/introducing-account-regional-namespaces-for-amazon-s3-general-purpose-buckets/). The full bucket name is constructed as `<bucket_name>-<account_id>-<region>-an`, ensuring only your account can own names with your suffix.

This module is designed for a Log Archive account in an AWS Organisation (typically via AWS Control Tower). VPC Flow Logs from any account in the organisation can be delivered to this bucket without enumerating individual account IDs.

## Usage

```hcl
module "flow_logs_bucket" {
  source = "rsclarke/flowlog-bucket/aws"

  bucket_name     = "vpc-flow-logs"
  organization_id = "o-abc123xyz"

  # Optional: set true to enforce SSE-KMS instead of SSE-S3.
  # If true and kms_key_arn is null, the module creates a dedicated KMS key.
  # use_kms     = true
  # kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"

  # Creates bucket: vpc-flow-logs-123456789012-eu-west-2-an
}

# Attach the read policy to roles that need to query flow logs:
#
# - security team:  attach module.flow_logs_bucket.read_policy_arn
# - audit role:     attach module.flow_logs_bucket.read_policy_arn
# - bucket name:    use module.flow_logs_bucket.bucket_name for the full
#                   computed bucket name
```

## Source-Account Flow Log Configuration

VPC Flow Logs are configured in each source account, not in this module. Use the `flow_logs_destination_arn` output as the log destination:

```hcl
resource "aws_flow_log" "vpc" {
  log_destination      = module.flow_logs_bucket.flow_logs_destination_arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.this.id

  destination_options {
    file_format                = "parquet"
    hive_compatible_partitions = true
    per_hour_partition         = true
  }
}
```

Hive-compatible partitions and hourly partitioning are recommended for Athena/Glue queryability. With these options the log path becomes:

```
s3://<bucket>/AWSLogs/aws-account-id=<id>/aws-service=vpcflowlogs/aws-region=<region>/year=YYYY/month=MM/day=DD/hour=HH/
```

Without them, the default path is:

```
s3://<bucket>/AWSLogs/<id>/vpcflowlogs/<region>/YYYY/MM/DD/
```

Both formats are covered by the lifecycle rule's `AWSLogs/` prefix filter.

## Encryption

This module supports three encryption modes:

- **SSE-S3 (default):** `use_kms = false`. Objects are encrypted with Amazon S3 managed keys (`AES256`). Simplest option for cross-account delivery.
- **SSE-KMS (module-managed key):** `use_kms = true`, `kms_key_arn = null`. The module creates a dedicated KMS key with key rotation enabled. The key policy grants `delivery.logs.amazonaws.com` encrypt access (scoped to your organisation) and the Log Archive account decrypt access via S3.
- **SSE-KMS (bring your own key):** `use_kms = true`, `kms_key_arn = "<arn>"`. Uses an externally managed KMS key. The key must be in the same region as the bucket and its policy must grant:
  - `delivery.logs.amazonaws.com` — `kms:Encrypt`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`, `kms:DescribeKey`
  - Log readers — `kms:Decrypt`, `kms:DescribeKey`

The bucket relies on default encryption configuration rather than SSE header enforcement, because the VPC Flow Logs delivery service does not send explicit encryption headers.

## Lifecycle And Retention

When `manage_lifecycle = true` (default), the module creates a lifecycle configuration with two rules:

| Rule | Scope | Behaviour |
|------|-------|-----------|
| `flow-logs-retention` | `AWSLogs/` prefix | 90d → Glacier, 365d → Deep Archive, 2555d (7 years) expiry |
| `cleanup` | Entire bucket | Expired delete marker cleanup, noncurrent version expiry at 30d, abort incomplete multipart uploads at 7d |

The 7-year retention covers most compliance frameworks (NIST, PCI-DSS, SOC 2). The lifecycle skips STANDARD_IA because VPC Flow Logs produce many small files where the 128 KB minimum object charge makes IA more expensive than Standard.

The `transition_default_minimum_object_size` is set to `varies_by_storage_class`, ensuring small flow log objects are still transitioned to archival tiers.

Set `manage_lifecycle = false` to manage lifecycle configuration externally via the `bucket_arn` output. This avoids resource conflicts when you need custom retention policies.

## Trust Model

This module scopes log delivery to a single AWS Organisation via the `aws:SourceOrgID` condition. Any account within that organisation can deliver VPC Flow Logs to this bucket without additional bucket policy changes.

The exported read IAM policy is bucket-wide (`${bucket}/*`). If you need to restrict read access to specific accounts or prefixes, attach caller-managed path-scoped IAM policies instead of (or in addition to) the module output.

The bucket policy denies all non-TLS requests to protect log data in transit.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.7 |
| aws | >= 6.37.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 6.37.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| bucket_name | Prefix for the S3 bucket name. The account-regional suffix is appended automatically. | `string` | n/a | yes |
| organization_id | AWS Organization ID. Scopes VPC Flow Log delivery to accounts within this organization. | `string` | n/a | yes |
| use_kms | Enable SSE-KMS mode. When false, SSE-S3 (`AES256`) is used. | `bool` | `false` | no |
| kms_key_arn | Existing KMS key ARN to use when `use_kms = true`. If null, the module creates a dedicated key. | `string` | `null` | no |
| manage_lifecycle | When true, creates a default lifecycle configuration. Set false to manage externally. | `bool` | `true` | no |
| force_destroy | Allow destruction of the bucket even when it contains objects. | `bool` | `false` | no |
| tags | Tags to apply to all resources created by this module. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| bucket_name | Full name of the S3 bucket (including account-regional suffix) |
| bucket_arn | ARN of the S3 bucket |
| read_policy_arn | ARN of the IAM policy granting read access to flow logs |
| kms_key_arn | Effective KMS key ARN when `use_kms = true`, otherwise `null` |
| flow_logs_destination_arn | Bucket ARN for use as `log_destination` in `aws_flow_log` resources |
