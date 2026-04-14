output "file_system_id" {
  value = aws_efs_file_system.masking.id
}

output "file_system_arn" {
  value = aws_efs_file_system.masking.arn
}

output "postgresql_access_point_id" {
  value = aws_efs_access_point.postgresql.id
}

output "postgresql_access_point_arn" {
  value = aws_efs_access_point.postgresql.arn
}

output "masking_access_point_id" {
  value = aws_efs_access_point.masking.id
}

output "masking_access_point_arn" {
  value = aws_efs_access_point.masking.arn
}

output "ssl_access_point_id" {
  value = aws_efs_access_point.ssl.id
}

output "ssl_access_point_arn" {
  value = aws_efs_access_point.ssl.arn
}

output "mount_target_ids" {
  value = [for mt in aws_efs_mount_target.this : mt.id]
}
