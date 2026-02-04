resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "masking" {
  family                   = "${local.name_prefix}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  volume {
    name = "postgresql-storage"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.masking.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.postgresql.id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "masking-storage"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.masking.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.masking.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    merge({
      name      = "database"
      image     = local.database_image
      essential = true
      cpu       = 0
      portMappings = [
        {
          name          = "database-5432-tcp"
          containerPort = 5432
          hostPort      = 5432
          protocol      = "tcp"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "postgresql-storage"
          containerPath = "/var/delphix/postgresql"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "database"
        }
      }
    }, local.repository_credentials),
    merge({
      name      = "app"
      image     = local.app_image
      essential = true
      cpu       = 0
      portMappings = [
        {
          name          = "app-8284-tcp"
          containerPort = 8284
          hostPort      = 8284
          protocol      = "tcp"
        },
        {
          name          = "app-15213-tcp"
          containerPort = 15213
          hostPort      = 15213
          protocol      = "tcp"
        }
      ]
      dependsOn = [
        {
          containerName = "database"
          condition     = "START"
        },
        {
          containerName = "proxy"
          condition     = "START"
        }
      ]
      environment = [
        {
          name  = "MASK_DEBUG"
          value = var.app_mask_debug
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "masking-storage"
          containerPath = "/var/delphix/masking"
          readOnly      = false
        },
        {
          sourceVolume  = "postgresql-storage"
          containerPath = "/var/delphix/postgresql"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "app"
        }
      }
    }, local.repository_credentials),
    merge({
      name      = "proxy"
      image     = local.proxy_image
      essential = true
      cpu       = 0
      portMappings = [
        {
          name          = "proxy-8080-tcp"
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
          appProtocol   = "http"
        },
        {
          name          = "proxy-8443-tcp"
          containerPort = 8443
          hostPort      = 8443
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "proxy"
        }
      }
    }, local.repository_credentials)
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "masking" {
  name            = "${local.name_prefix}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.masking.arn
  launch_type     = "FARGATE"
  desired_count   = var.desired_count

  network_configuration {
    subnets          = local.effective_ecs_subnet_ids
    assign_public_ip = var.assign_public_ip
    security_groups  = [aws_security_group.ecs_tasks.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.proxy.arn
    container_name   = "proxy"
    container_port   = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  health_check_grace_period_seconds  = 120

  depends_on = [
    aws_iam_role_policy_attachment.ecs_execution_managed,
    aws_lb_listener.http,
    aws_efs_mount_target.this
  ]

  tags = local.common_tags
}
