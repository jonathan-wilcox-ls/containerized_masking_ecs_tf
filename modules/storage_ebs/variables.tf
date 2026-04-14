variable "infrastructure_role_arn" {
  description = "ECS infrastructure role ARN for managed EBS"
  type        = string
}

variable "volume_type" {
  description = "EBS volume type"
  type        = string
  default     = "gp3"
}

variable "postgresql_size_in_gb" {
  description = "PostgreSQL EBS size in GiB"
  type        = number
  default     = 20
}

variable "masking_size_in_gb" {
  description = "Masking EBS size in GiB"
  type        = number
  default     = 50
}

variable "filesystem_type" {
  description = "Filesystem type for managed EBS"
  type        = string
  default     = "xfs"
}

variable "kms_key_id" {
  description = "Optional KMS key ID/ARN for EBS encryption"
  type        = string
  default     = null
}

variable "snapshot_id" {
  description = "Optional EBS snapshot ID to seed the managed volume"
  type        = string
  default     = null
}

variable "iops" {
  description = "Optional provisioned IOPS when supported by the selected volume type"
  type        = number
  default     = null
}

variable "throughput" {
  description = "Optional throughput in MiB/s when supported by the selected volume type"
  type        = number
  default     = null
}

variable "volume_initialization_rate" {
  description = "Optional snapshot initialization rate in MiB/s"
  type        = number
  default     = null
}

variable "volume_tags" {
  description = "Additional tags to apply directly to the managed EBS volume"
  type        = map(string)
  default     = {}
}

variable "postgresql_extra_configuration" {
  description = "Optional additional fields to merge into postgresql volume_configuration"
  type        = map(any)
  default     = {}
}

variable "masking_extra_configuration" {
  description = "Optional additional fields to merge into masking volume_configuration"
  type        = map(any)
  default     = {}
}
