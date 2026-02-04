output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.masking.name
}

output "ecs_task_definition_arn" {
  description = "Task definition ARN"
  value       = aws_ecs_task_definition.masking.arn
}

output "alb_dns_name" {
  description = "Public ALB DNS name"
  value       = aws_lb.this.dns_name
}

output "service_url" {
  description = "Service URL (HTTP by default, HTTPS when ACM is configured)"
  value       = "${local.enable_https ? "https" : "http"}://${var.create_acm_certificate ? var.acm_domain_name : aws_lb.this.dns_name}"
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for task containers"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "efs_id" {
  description = "EFS filesystem ID backing persistent storage"
  value       = aws_efs_file_system.masking.id
}

output "vpc_id" {
  description = "VPC ID used by the deployment"
  value       = local.effective_vpc_id
}

output "alb_subnet_ids" {
  description = "ALB subnet IDs in use"
  value       = local.effective_alb_subnet_ids
}

output "ecs_subnet_ids" {
  description = "ECS task subnet IDs in use"
  value       = local.effective_ecs_subnet_ids
}
