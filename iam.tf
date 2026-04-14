data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${local.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_repo_credentials" {
  count = var.repository_credentials_secret_arn == null ? 0 : 1

  name = "${local.name_prefix}-repo-credentials-access"
  role = aws_iam_role.ecs_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          var.repository_credentials_secret_arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
  tags               = local.common_tags
}

# Allow containers to mount and write via EFS access points when IAM auth is enabled.
data "aws_iam_policy_document" "ecs_task_efs" {
  count = var.storage_backend == "efs" ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:DescribeMountTargets"
    ]
    resources = [
      module.storage_efs[0].file_system_arn,
      module.storage_efs[0].postgresql_access_point_arn,
      module.storage_efs[0].masking_access_point_arn,
      module.storage_efs[0].ssl_access_point_arn
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_efs" {
  count = var.storage_backend == "efs" ? 1 : 0

  name   = "${local.name_prefix}-efs-access"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_efs[0].json
}

data "aws_iam_policy_document" "ecs_task_jdbc_tls_source" {
  count = var.enable_jdbc_tls_init ? 1 : 0

  dynamic "statement" {
    for_each = local.jdbc_tls_s3_object_arn == null ? [] : [1]
    content {
      effect = "Allow"
      actions = [
        "s3:GetObject"
      ]
      resources = [
        local.jdbc_tls_s3_object_arn
      ]
    }
  }

  dynamic "statement" {
    for_each = var.jdbc_tls_cert_source_secret_arn == null ? [] : [1]
    content {
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue"
      ]
      resources = [
        var.jdbc_tls_cert_source_secret_arn
      ]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_task_jdbc_tls_source" {
  count = var.enable_jdbc_tls_init ? 1 : 0

  name   = "${local.name_prefix}-jdbc-tls-source-access"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_jdbc_tls_source[0].json
}

resource "aws_iam_role_policy" "ecs_task_exec" {
  name = "${local.name_prefix}-ecs-exec"
  role = aws_iam_role.ecs_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}
