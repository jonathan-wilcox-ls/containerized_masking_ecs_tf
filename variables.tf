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
  description = "Subnet IDs for the internet-facing ALB"
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

variable "create_dev_network" {
  description = "Create a dev VPC with 2 public + 2 private subnets"
  type        = bool
  default     = true
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
  default     = "/"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
