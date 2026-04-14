variable "name_prefix" {
  description = "Name prefix"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "ecs_tasks_security_group_id" {
  description = "ECS task security group ID"
  type        = string
}

variable "efs_subnet_map" {
  description = "Map of subnet IDs for EFS mount targets"
  type        = map(string)
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
}
