variable "bucket_name" {
  description = "Prefix for the S3 bucket name. The account-regional suffix (-<account_id>-<region>-an) is appended automatically."
  type        = string

  validation {
    condition     = length(var.bucket_name) <= 32 && can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name prefix must be <= 32 characters, contain only lowercase alphanumeric characters and hyphens, and not start or end with a hyphen."
  }
}

variable "organization_id" {
  description = "AWS Organization ID. Scopes VPC Flow Log delivery to accounts within this organization."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id must be a valid AWS Organization ID (e.g. o-abc123xyz)."
  }
}

variable "use_kms" {
  description = "Enable SSE-KMS instead of SSE-S3. When true, this module enforces aws:kms object encryption."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Existing KMS key ARN to use when use_kms is true. If null, this module creates and manages a dedicated KMS key. The key must be in the same region as the bucket and its policy must grant delivery.logs.amazonaws.com encrypt permissions."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[^:]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be null or a valid KMS key ARN."
  }
}

variable "manage_lifecycle" {
  description = "When true, creates a default lifecycle configuration (90d→Glacier, 365d→Deep Archive, 7y expiry). Set to false to manage lifecycle externally via the bucket ARN output."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow destruction of the bucket even when it contains objects."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
