resource "aws_security_group" "efs" {
  name        = "${local.name_prefix}-efs-sg"
  description = "Allow NFS from ECS tasks"
  vpc_id      = local.effective_vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-efs-sg" })
}

resource "aws_efs_file_system" "masking" {
  creation_token = "${local.name_prefix}-efs"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-efs" })
}

resource "aws_efs_mount_target" "this" {
  for_each = local.effective_efs_subnet_map

  file_system_id  = aws_efs_file_system.masking.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "postgresql" {
  file_system_id = aws_efs_file_system.masking.id

  posix_user {
    gid = 50
    uid = 65436
  }

  root_directory {
    path = "/postgresql"
    creation_info {
      owner_gid   = 50
      owner_uid   = 65436
      permissions = "0775"
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-postgresql-ap" })
}

resource "aws_efs_access_point" "masking" {
  file_system_id = aws_efs_file_system.masking.id

  posix_user {
    gid = 50
    uid = 65436
  }

  root_directory {
    path = "/masking"
    creation_info {
      owner_gid   = 50
      owner_uid   = 65436
      permissions = "0775"
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-masking-ap" })
}
