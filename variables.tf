variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "delphix-masking"
}

variable "vpc_id" {
  description = "VPC ID for ECS/ALB/EFS resources"
  type        = string
  default     = null
}

variable "alb_subnet_ids" {
  description = "Subnet IDs for ALB (used when create_dev_network is false and either alb_internal is false or alb_private_subnet_ids is empty)"
  type        = list(string)
  default     = []
}

variable "alb_internal" {
  description = "Whether the ALB is internal-only (private)"
  type        = bool
  default     = false
}

variable "alb_private_subnet_ids" {
  description = "Private subnet IDs for an internal ALB when create_dev_network is false"
  type        = list(string)
  default     = []
}

variable "alb_ingress_cidrs" {
  description = "CIDR allowlist for ALB inbound (HTTP/HTTPS)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ecs_subnet_ids" {
  description = "Subnet IDs where ECS tasks run"
  type        = list(string)
  default     = []
}

variable "efs_subnet_ids" {
  description = "Subnet IDs for EFS mount targets"
  type        = list(string)
  default     = []
}

variable "storage_backend" {
  description = "Persistent storage backend for task data: efs or ebs"
  type        = string
  default     = "efs"

  validation {
    condition     = contains(["efs", "ebs"], var.storage_backend)
    error_message = "storage_backend must be either \"efs\" or \"ebs\"."
  }
}

variable "ecs_infrastructure_role_arn" {
  description = "ECS infrastructure role ARN required for managed EBS volumes"
  type        = string
  default     = null
}

variable "ebs_volume_type" {
  description = "EBS volume type when storage_backend is ebs"
  type        = string
  default     = "gp3"
}

variable "ebs_postgresql_size_in_gb" {
  description = "EBS volume size in GiB for /var/delphix/postgresql when using ebs"
  type        = number
  default     = 20
}

variable "ebs_masking_size_in_gb" {
  description = "EBS volume size in GiB for /var/delphix/masking when using ebs"
  type        = number
  default     = 50
}

variable "ebs_filesystem_type" {
  description = "Filesystem type for managed EBS volumes"
  type        = string
  default     = "xfs"
}

variable "ebs_kms_key_id" {
  description = "Optional KMS key ID/ARN for managed EBS encryption"
  type        = string
  default     = null
}

variable "ebs_snapshot_id" {
  description = "Optional EBS snapshot ID to use when creating managed ECS service volumes"
  type        = string
  default     = null
}

variable "ebs_iops" {
  description = "Optional provisioned IOPS for managed EBS volumes when supported by the selected volume type"
  type        = number
  default     = null
}

variable "ebs_throughput" {
  description = "Optional throughput in MiB/s for managed EBS volumes when supported by the selected volume type"
  type        = number
  default     = null
}

variable "ebs_volume_initialization_rate" {
  description = "Optional snapshot initialization rate in MiB/s when creating managed EBS volumes from a snapshot"
  type        = number
  default     = null
}

variable "ebs_volume_tags" {
  description = "Additional tags to apply directly to ECS-managed EBS volumes"
  type        = map(string)
  default     = {}
}

variable "create_dev_network" {
  description = "Create a dev VPC with 2 public + 2 private subnets"
  type        = bool
  default     = true
}

variable "enable_private_aws_endpoints" {
  description = "Create VPC endpoints for AWS services to reduce NAT traffic (when create_dev_network is true)"
  type        = bool
  default     = true
}

variable "interface_endpoint_services" {
  description = "Interface endpoint service suffixes to create in the VPC"
  type        = list(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
    "kms",
    "sts"
  ]
}

variable "dev_vpc_cidr" {
  description = "CIDR block for generated dev VPC"
  type        = string
  default     = "10.42.0.0/16"
}

variable "dev_public_subnet_cidrs" {
  description = "Two CIDRs for generated public subnets"
  type        = list(string)
  default     = ["10.42.0.0/24", "10.42.1.0/24"]

  validation {
    condition     = length(var.dev_public_subnet_cidrs) == 2
    error_message = "dev_public_subnet_cidrs must contain exactly 2 CIDR blocks."
  }
}

variable "dev_private_subnet_cidrs" {
  description = "Two CIDRs for generated private subnets"
  type        = list(string)
  default     = ["10.42.10.0/24", "10.42.11.0/24"]

  validation {
    condition     = length(var.dev_private_subnet_cidrs) == 2
    error_message = "dev_private_subnet_cidrs must contain exactly 2 CIDR blocks."
  }
}

variable "assign_public_ip" {
  description = "Assign public IPs to ECS tasks"
  type        = bool
  default     = false
}

variable "task_cpu" {
  description = "Task-level CPU units (for Fargate)"
  type        = number
  default     = 8192
}

variable "task_memory" {
  description = "Task-level memory in MiB (for Fargate)"
  type        = number
  default     = 16384
}

variable "desired_count" {
  description = "Desired ECS service task count"
  type        = number
  default     = 1
}

variable "docker_registry_url" {
  description = "Container registry URL/repository prefix (without image tag)"
  type        = string
}

variable "masking_database_image_tag" {
  description = "Masking database image tag"
  type        = string
}

variable "masking_app_image_tag" {
  description = "Masking app image tag"
  type        = string
}

variable "masking_proxy_image_tag" {
  description = "Masking proxy image tag"
  type        = string
}

variable "repository_credentials_secret_arn" {
  description = "Optional Secrets Manager ARN for private non-ECR registry credentials"
  type        = string
  default     = null
}

variable "enable_jdbc_tls_init" {
  description = "Enable init-style sidecar to build JDBC TLS truststore from S3 or Secrets Manager before app startup"
  type        = bool
  default     = false
}

variable "jdbc_tls_init_image" {
  description = "Optional image for JDBC TLS init sidecar; defaults to masking app image when null"
  type        = string
  default     = null
}

variable "jdbc_tls_cert_source_s3_uri" {
  description = "Optional S3 URI (s3://bucket/key.pem) for JDBC TLS certificate bundle source"
  type        = string
  default     = null

  validation {
    condition     = var.jdbc_tls_cert_source_s3_uri == null ? true : startswith(var.jdbc_tls_cert_source_s3_uri, "s3://")
    error_message = "jdbc_tls_cert_source_s3_uri must start with \"s3://\" when set."
  }
}

variable "jdbc_tls_cert_source_secret_arn" {
  description = "Optional Secrets Manager ARN containing JDBC TLS certificate bundle in SecretString PEM format"
  type        = string
  default     = null
}

variable "jdbc_tls_truststore_password" {
  description = "Password for generated JDBC TLS truststore"
  type        = string
  default     = "changeit"
}

variable "certificate_arn" {
  description = "Optional ACM certificate ARN for HTTPS listener"
  type        = string
  default     = null
}

variable "create_acm_certificate" {
  description = "Create and validate an ACM certificate using Route53"
  type        = bool
  default     = false
}

variable "acm_domain_name" {
  description = "FQDN to use on ACM cert and Route53 alias (for example masking-dev.example.com)"
  type        = string
  default     = null
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS validation and alias record"
  type        = string
  default     = null
}

variable "create_service_dns_record" {
  description = "Create Route53 alias record for acm_domain_name to the ALB when zone/domain are provided"
  type        = bool
  default     = true
}

variable "app_mask_debug" {
  description = "MASK_DEBUG value for app container"
  type        = string
  default     = "true"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "health_check_path" {
  description = "ALB target group health check path"
  type        = string
  default     = "/masking/login.do"
}

variable "service_health_check_grace_period_seconds" {
  description = "ECS service health check grace period before ALB failures count against task health"
  type        = number
  default     = 120
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
