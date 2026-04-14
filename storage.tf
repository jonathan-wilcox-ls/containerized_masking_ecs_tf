module "storage_efs" {
  count = var.storage_backend == "efs" ? 1 : 0

  source = "./modules/storage_efs"

  name_prefix                 = local.name_prefix
  vpc_id                      = local.effective_vpc_id
  ecs_tasks_security_group_id = aws_security_group.ecs_tasks.id
  efs_subnet_map              = local.effective_efs_subnet_map
  tags                        = local.common_tags
}

module "storage_ebs" {
  count = var.storage_backend == "ebs" ? 1 : 0

  source = "./modules/storage_ebs"

  infrastructure_role_arn    = var.ecs_infrastructure_role_arn
  volume_type                = var.ebs_volume_type
  postgresql_size_in_gb      = var.ebs_postgresql_size_in_gb
  masking_size_in_gb         = var.ebs_masking_size_in_gb
  filesystem_type            = var.ebs_filesystem_type
  kms_key_id                 = var.ebs_kms_key_id
  snapshot_id                = var.ebs_snapshot_id
  iops                       = var.ebs_iops
  throughput                 = var.ebs_throughput
  volume_initialization_rate = var.ebs_volume_initialization_rate
  volume_tags                = var.ebs_volume_tags
}

locals {
  postgresql_source_volume = var.storage_backend == "ebs" ? "persistent-storage" : "postgresql-storage"
  masking_source_volume    = var.storage_backend == "ebs" ? "persistent-storage" : "masking-storage"
  ssl_source_volume        = var.storage_backend == "ebs" ? "persistent-storage" : "ssl-storage"
  shared_storage_path      = "/var/delphix"
  masking_storage_path     = "/var/delphix/masking"
  ssl_storage_path         = "${local.shared_storage_path}/ssl"
  jdbc_tls_mount_path      = var.storage_backend == "ebs" ? local.shared_storage_path : local.ssl_storage_path
  jdbc_tls_ssl_path        = local.ssl_storage_path

  database_mount_points = var.storage_backend == "ebs" ? [
    {
      sourceVolume  = local.postgresql_source_volume
      containerPath = local.shared_storage_path
      readOnly      = false
    }
    ] : [
    {
      sourceVolume  = local.postgresql_source_volume
      containerPath = "/var/delphix/postgresql"
      readOnly      = false
    }
  ]

  app_mount_points = var.storage_backend == "ebs" ? [
    {
      sourceVolume  = local.masking_source_volume
      containerPath = local.shared_storage_path
      readOnly      = false
    }
    ] : [
    {
      sourceVolume  = local.masking_source_volume
      containerPath = "/var/delphix/masking"
      readOnly      = false
    },
    {
      sourceVolume  = local.postgresql_source_volume
      containerPath = "/var/delphix/postgresql"
      readOnly      = false
    },
    {
      sourceVolume  = local.ssl_source_volume
      containerPath = local.ssl_storage_path
      readOnly      = false
    }
  ]

  storage_task_volumes = var.storage_backend == "efs" ? [
    {
      name           = local.postgresql_source_volume
      type           = "efs"
      file_system_id = module.storage_efs[0].file_system_id
      access_point   = module.storage_efs[0].postgresql_access_point_id
    },
    {
      name           = local.masking_source_volume
      type           = "efs"
      file_system_id = module.storage_efs[0].file_system_id
      access_point   = module.storage_efs[0].masking_access_point_id
    },
    {
      name           = local.ssl_source_volume
      type           = "efs"
      file_system_id = module.storage_efs[0].file_system_id
      access_point   = module.storage_efs[0].ssl_access_point_id
    }
    ] : [
    {
      name = local.postgresql_source_volume
      type = "ebs"
    }
  ]

  storage_service_volume_configurations = var.storage_backend == "ebs" ? module.storage_ebs[0].service_volume_configurations : []
}
