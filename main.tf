terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  database_image = "${var.docker_registry_url}:${var.masking_database_image_tag}"
  app_image      = "${var.docker_registry_url}:${var.masking_app_image_tag}"
  proxy_image    = "${var.docker_registry_url}:${var.masking_proxy_image_tag}"
  repository_credentials = var.repository_credentials_secret_arn == null ? {} : {
    repositoryCredentials = {
      credentialsParameter = var.repository_credentials_secret_arn
    }
  }
  jdbc_tls_s3_uri_no_scheme = var.jdbc_tls_cert_source_s3_uri == null ? null : trimprefix(var.jdbc_tls_cert_source_s3_uri, "s3://")
  jdbc_tls_s3_parts         = var.jdbc_tls_cert_source_s3_uri == null ? [] : split("/", local.jdbc_tls_s3_uri_no_scheme)
  jdbc_tls_s3_bucket        = length(local.jdbc_tls_s3_parts) > 0 ? local.jdbc_tls_s3_parts[0] : null
  jdbc_tls_s3_key           = length(local.jdbc_tls_s3_parts) > 1 ? join("/", slice(local.jdbc_tls_s3_parts, 1, length(local.jdbc_tls_s3_parts))) : null
  jdbc_tls_s3_object_arn    = local.jdbc_tls_s3_bucket != null && local.jdbc_tls_s3_key != null ? "arn:aws:s3:::${local.jdbc_tls_s3_bucket}/${local.jdbc_tls_s3_key}" : null

  effective_vpc_id = var.create_dev_network ? aws_vpc.dev[0].id : var.vpc_id

  effective_alb_subnet_ids = var.create_dev_network ? (
    var.alb_internal ?
    [for k in sort(keys(aws_subnet.private)) : aws_subnet.private[k].id] :
    [for k in sort(keys(aws_subnet.public)) : aws_subnet.public[k].id]
    ) : (
    var.alb_internal && length(var.alb_private_subnet_ids) > 0 ?
    var.alb_private_subnet_ids :
    var.alb_subnet_ids
  )

  effective_ecs_subnet_ids  = var.create_dev_network ? [for k in sort(keys(aws_subnet.private)) : aws_subnet.private[k].id] : var.ecs_subnet_ids
  effective_efs_subnet_map  = var.create_dev_network ? { for k, subnet in aws_subnet.private : k => subnet.id } : { for i, subnet_id in var.efs_subnet_ids : tostring(i) => subnet_id }
  effective_efs_subnet_ids  = values(local.effective_efs_subnet_map)
  effective_certificate_arn = var.create_acm_certificate ? aws_acm_certificate_validation.this[0].certificate_arn : var.certificate_arn

  enable_https = var.create_acm_certificate || (var.certificate_arn != null && var.certificate_arn != "")
  create_service_alias = (
    var.create_service_dns_record &&
    var.route53_zone_id != null &&
    var.route53_zone_id != "" &&
    var.acm_domain_name != null &&
    var.acm_domain_name != ""
  )
}
