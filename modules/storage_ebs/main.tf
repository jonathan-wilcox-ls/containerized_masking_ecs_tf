locals {
  maybe_kms = var.kms_key_id == null ? {} : {
    kms_key_id = var.kms_key_id
  }

  maybe_snapshot = var.snapshot_id == null ? {} : {
    snapshot_id = var.snapshot_id
  }

  maybe_iops = var.iops == null ? {} : {
    iops = var.iops
  }

  maybe_throughput = var.throughput == null ? {} : {
    throughput = var.throughput
  }

  maybe_volume_initialization_rate = var.volume_initialization_rate == null ? {} : {
    volume_initialization_rate = var.volume_initialization_rate
  }

  maybe_volume_tags = length(var.volume_tags) == 0 ? {} : {
    tags = var.volume_tags
  }

  managed_ebs_volume = merge({
    encrypted        = true
    role_arn         = var.infrastructure_role_arn
    volume_type      = var.volume_type
    size_in_gb       = max(var.postgresql_size_in_gb, var.masking_size_in_gb)
    file_system_type = var.filesystem_type
    tag_specifications = [
      merge({
        resource_type  = "volume"
        propagate_tags = "SERVICE"
      }, local.maybe_volume_tags)
    ]
  }, local.maybe_kms, local.maybe_snapshot, local.maybe_iops, local.maybe_throughput, local.maybe_volume_initialization_rate)

  # ECS service supports a single volume_configuration block for managed EBS.
  # Use one shared volume sized to the larger requested directory size.
  shared_volume_configuration = merge({
    name               = "persistent-storage"
    managed_ebs_volume = local.managed_ebs_volume
  }, var.postgresql_extra_configuration, var.masking_extra_configuration)
}
