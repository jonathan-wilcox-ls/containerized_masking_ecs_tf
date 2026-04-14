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

locals {
  app_container_depends_on = concat([
    {
      containerName = "database"
      condition     = "START"
    },
    {
      containerName = "proxy"
      condition     = "START"
    }
    ],
    var.enable_jdbc_tls_init ? [
      {
        containerName = "jdbc-truststore-init"
        condition     = "SUCCESS"
      }
    ] : []
  )

  jdbc_tls_init_command = trimspace(<<-EOT
    set -eu;
    mkdir -p "$JDBC_TLS_SSL_PATH" "$JDBC_TLS_SSL_PATH/split";
    rm -f "$JDBC_TLS_SSL_PATH/source.pem" "$JDBC_TLS_SSL_PATH/.masking_certs";
    rm -f "$JDBC_TLS_SSL_PATH/split/"*.crt;
    if [ -n "$JDBC_TLS_CERT_SOURCE_S3_URI" ]; then
      aws s3 cp "$JDBC_TLS_CERT_SOURCE_S3_URI" "$JDBC_TLS_SSL_PATH/source.pem";
    elif [ -n "$JDBC_TLS_CERT_SOURCE_SECRET_ARN" ]; then
      aws secretsmanager get-secret-value --secret-id "$JDBC_TLS_CERT_SOURCE_SECRET_ARN" --query SecretString --output text > "$JDBC_TLS_SSL_PATH/source.pem";
    else
      echo "No JDBC TLS certificate source configured";
      exit 1;
    fi;
    awk -v outdir="$JDBC_TLS_SSL_PATH/split" 'BEGIN{n=0} /BEGIN CERTIFICATE/{n++; f=sprintf("%s/cert-%02d.crt", outdir, n)} {if(n>0) print > f} /END CERTIFICATE/{close(f)}' "$JDBC_TLS_SSL_PATH/source.pem";
    certs="$(find "$JDBC_TLS_SSL_PATH/split" -maxdepth 1 -type f -name '*.crt' | sort)";
    [ -n "$certs" ] || { echo "No certificates extracted from certificate source"; exit 1; };
    for f in $certs; do
      alias_name="$(basename "$f" .crt)";
      keytool -import -trustcacerts -keystore "$JDBC_TLS_SSL_PATH/.masking_certs" -storepass "$JDBC_TLS_TRUSTSTORE_PASSWORD" -noprompt -alias "$alias_name" -file "$f";
    done;
    keytool -list -keystore "$JDBC_TLS_SSL_PATH/.masking_certs" -storepass "$JDBC_TLS_TRUSTSTORE_PASSWORD";
  EOT
  )

  jdbc_tls_init_container_definitions = var.enable_jdbc_tls_init ? [merge({
    name       = "jdbc-truststore-init"
    image      = coalesce(var.jdbc_tls_init_image, local.app_image)
    essential  = false
    cpu        = 0
    entryPoint = ["/bin/sh", "-lc"]
    command    = [local.jdbc_tls_init_command]
    mountPoints = [
      {
        sourceVolume  = local.ssl_source_volume
        containerPath = local.jdbc_tls_mount_path
        readOnly      = false
      }
    ]
    environment = [
      {
        name  = "AWS_REGION"
        value = data.aws_region.current.name
      },
      {
        name  = "JDBC_TLS_SSL_PATH"
        value = local.jdbc_tls_ssl_path
      },
      {
        name  = "JDBC_TLS_CERT_SOURCE_S3_URI"
        value = var.jdbc_tls_cert_source_s3_uri != null ? var.jdbc_tls_cert_source_s3_uri : ""
      },
      {
        name  = "JDBC_TLS_CERT_SOURCE_SECRET_ARN"
        value = var.jdbc_tls_cert_source_secret_arn != null ? var.jdbc_tls_cert_source_secret_arn : ""
      },
      {
        name  = "JDBC_TLS_TRUSTSTORE_PASSWORD"
        value = var.jdbc_tls_truststore_password
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "jdbc-truststore-init"
      }
    }
  }, local.repository_credentials)] : []
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

  dynamic "volume" {
    for_each = local.storage_task_volumes
    content {
      name                = volume.value.name
      configure_at_launch = volume.value.type == "ebs"

      dynamic "efs_volume_configuration" {
        for_each = volume.value.type == "efs" ? [1] : []
        content {
          file_system_id     = volume.value.file_system_id
          transit_encryption = "ENABLED"

          authorization_config {
            access_point_id = volume.value.access_point
            iam             = "ENABLED"
          }
        }
      }
    }
  }

  container_definitions = jsonencode(concat([
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
      mountPoints = local.database_mount_points
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
      dependsOn = local.app_container_depends_on
      environment = [
        {
          name  = "MASK_DEBUG"
          value = var.app_mask_debug
        }
      ]
      mountPoints = local.app_mount_points
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
  ], local.jdbc_tls_init_container_definitions))

  tags = local.common_tags
}

resource "aws_ecs_service" "masking" {
  name                    = "${local.name_prefix}-service"
  cluster                 = aws_ecs_cluster.this.id
  task_definition         = aws_ecs_task_definition.masking.arn
  launch_type             = "FARGATE"
  desired_count           = var.desired_count
  enable_ecs_managed_tags = true
  enable_execute_command  = true
  propagate_tags          = "SERVICE"

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

  dynamic "volume_configuration" {
    for_each = local.storage_service_volume_configurations
    content {
      name = volume_configuration.value.name

      managed_ebs_volume {
        encrypted                  = volume_configuration.value.managed_ebs_volume.encrypted
        role_arn                   = volume_configuration.value.managed_ebs_volume.role_arn
        volume_type                = volume_configuration.value.managed_ebs_volume.volume_type
        size_in_gb                 = volume_configuration.value.managed_ebs_volume.size_in_gb
        file_system_type           = volume_configuration.value.managed_ebs_volume.file_system_type
        iops                       = try(volume_configuration.value.managed_ebs_volume.iops, null)
        kms_key_id                 = try(volume_configuration.value.managed_ebs_volume.kms_key_id, null)
        snapshot_id                = try(volume_configuration.value.managed_ebs_volume.snapshot_id, null)
        throughput                 = try(volume_configuration.value.managed_ebs_volume.throughput, null)
        volume_initialization_rate = try(volume_configuration.value.managed_ebs_volume.volume_initialization_rate, null)

        dynamic "tag_specifications" {
          for_each = try(volume_configuration.value.managed_ebs_volume.tag_specifications, [])
          content {
            resource_type  = tag_specifications.value.resource_type
            propagate_tags = try(tag_specifications.value.propagate_tags, null)
            tags           = try(tag_specifications.value.tags, null)
          }
        }
      }
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  health_check_grace_period_seconds  = var.service_health_check_grace_period_seconds

  depends_on = [
    aws_iam_role_policy_attachment.ecs_execution_managed,
    aws_lb_listener.http
  ]

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = var.storage_backend != "ebs" || (var.ecs_infrastructure_role_arn != null && var.ecs_infrastructure_role_arn != "")
      error_message = "ecs_infrastructure_role_arn must be set when storage_backend is \"ebs\"."
    }
    precondition {
      condition     = var.storage_backend != "ebs" || var.desired_count == 1
      error_message = "desired_count must be 1 when storage_backend is \"ebs\" because ECS creates one managed EBS volume per service task."
    }
    precondition {
      condition     = var.ebs_volume_initialization_rate == null || var.ebs_snapshot_id != null
      error_message = "ebs_volume_initialization_rate requires ebs_snapshot_id to be set."
    }
    precondition {
      condition     = var.ebs_iops == null || contains(["gp3", "io1", "io2"], var.ebs_volume_type)
      error_message = "ebs_iops is supported only for gp3, io1, or io2 volumes."
    }
    precondition {
      condition     = var.ebs_throughput == null || var.ebs_volume_type == "gp3"
      error_message = "ebs_throughput is supported only when ebs_volume_type is \"gp3\"."
    }
    precondition {
      condition = !var.enable_jdbc_tls_init || (
        (var.jdbc_tls_cert_source_s3_uri != null && var.jdbc_tls_cert_source_secret_arn == null) ||
        (var.jdbc_tls_cert_source_s3_uri == null && var.jdbc_tls_cert_source_secret_arn != null)
      )
      error_message = "When enable_jdbc_tls_init is true, set exactly one of jdbc_tls_cert_source_s3_uri or jdbc_tls_cert_source_secret_arn."
    }
    precondition {
      condition     = var.jdbc_tls_cert_source_s3_uri == null ? true : length(split("/", trimprefix(var.jdbc_tls_cert_source_s3_uri, "s3://"))) > 1
      error_message = "jdbc_tls_cert_source_s3_uri must include both bucket and object key (for example s3://bucket/path/certs.pem)."
    }
  }
}
