resource "aws_security_group" "efs" {
  name        = "${var.name_prefix}-efs-sg"
  description = "Allow NFS from ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [var.ecs_tasks_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-efs-sg" })
}

resource "aws_efs_file_system" "masking" {
  creation_token = "${var.name_prefix}-efs"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-efs" })
}

resource "aws_efs_mount_target" "this" {
  for_each = var.efs_subnet_map

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

  tags = merge(var.tags, { Name = "${var.name_prefix}-postgresql-ap" })
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

  tags = merge(var.tags, { Name = "${var.name_prefix}-masking-ap" })
}

resource "aws_efs_access_point" "ssl" {
  file_system_id = aws_efs_file_system.masking.id

  posix_user {
    gid = 50
    uid = 65436
  }

  root_directory {
    path = "/ssl"
    creation_info {
      owner_gid   = 50
      owner_uid   = 65436
      permissions = "0775"
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-ssl-ap" })
}
