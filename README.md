# Delphix Masking on AWS ECS/Fargate (Terraform)

This folder is an ECS/Fargate variant of the existing Kubernetes deployment.

## What it deploys

- ECS cluster, task definition, and Fargate service
- Three core containers in one task (`database`, `app`, `proxy`)
- Optional fourth sidecar container: `jdbc-truststore-init` when `enable_jdbc_tls_init = true`
- ALB routing:
  - `/` -> proxy container on `8080`
- HTTPS via ACM (existing ARN or optional ACM+Route53 creation)
- Persistent storage for:
  - `/var/delphix/postgresql`
  - `/var/delphix/masking`
  - `/var/delphix/ssl`
  - Backends:
    - `efs` (default): EFS + access points
    - `ebs`: ECS managed EBS using one shared volume mounted at `/var/delphix`
- CloudWatch log group
- IAM roles for ECS execution/task + EFS

## Dev-friendly networking

By default, this stack can create a complete dev VPC (`create_dev_network = true`):

- 2 public subnets for ALB
- 2 private subnets for ECS/EFS
- Internet Gateway + NAT Gateway
- Route tables and associations
- Private AWS VPC endpoints (enabled by default) for reduced NAT egress:
  - `ecr.api`, `ecr.dkr`, `logs`, `secretsmanager`, `kms`, `sts`, and S3 gateway

If you already have networking, set `create_dev_network = false` and provide:

- `vpc_id`
- `alb_subnet_ids`
- `ecs_subnet_ids`
- `efs_subnet_ids` (only used when `storage_backend = "efs"`)
- `alb_private_subnet_ids` (optional, used when `alb_internal = true`)

You can also restrict ALB ingress with:
- `alb_ingress_cidrs` (defaults to `["0.0.0.0/0"]`)
- Set `alb_internal = true` to make the ALB private-only.

Endpoint toggles:
- `enable_private_aws_endpoints` (default `true`)
- `interface_endpoint_services` (override list if you want fewer/more endpoints)
- If you want ECS Exec in a fully private environment without NAT, also include `ssm`, `ssmmessages`, and `ec2messages` interface endpoints.

## HTTPS options

Use one of these:

1. Existing cert: set `certificate_arn`
2. New cert in Terraform: set all of:
   - `create_acm_certificate = true`
   - `acm_domain_name` (for example `masking-dev.example.com`)
   - `route53_zone_id`

DNS alias record:
- `create_service_dns_record` defaults to `true` and creates an alias for `acm_domain_name` to the ALB when both `acm_domain_name` and `route53_zone_id` are set.
- Set `create_service_dns_record = false` if you want ACM validation records only and do not want Terraform to create the service alias.
- For private-only service, use a Route53 private hosted zone ID.

## Required image inputs

- `docker_registry_url`
- `masking_database_image_tag`
- `masking_app_image_tag`
- `masking_proxy_image_tag`

## Storage backend options

Use `storage_backend` to choose persistent storage:

- `storage_backend = "efs"` (default)
  - Shared persistent storage via EFS access points.
  - Requires EFS mount target subnets (generated automatically when `create_dev_network = true`).
- `storage_backend = "ebs"`
  - Uses ECS managed EBS for persistent task storage.
  - Requires `ecs_infrastructure_role_arn`.
  - ECS currently allows one managed EBS service volume configuration; this stack uses one shared EBS volume mounted at `/var/delphix`.
  - Service-managed EBS volumes are deleted when the service task stops. Use the snapshot workflow below to preserve state across deployments.
  - Optional tuning:
    - `ebs_volume_type` (default `gp3`)
    - `ebs_postgresql_size_in_gb` (default `20`)
    - `ebs_masking_size_in_gb` (default `50`)
    - `ebs_filesystem_type` (default `xfs`)
    - `ebs_kms_key_id` (optional CMK)
    - `ebs_snapshot_id` (restore new task volume from a prior snapshot)
    - `ebs_iops` (for `gp3`, `io1`, `io2`)
    - `ebs_throughput` (for `gp3`)
    - `ebs_volume_initialization_rate` (requires `ebs_snapshot_id`)
    - `ebs_volume_tags` (additional direct volume tags)

Example (EBS):

```hcl
storage_backend             = "ebs"
ecs_infrastructure_role_arn = "arn:aws:iam::<account-id>:role/ecsInfrastructureRole"
ebs_volume_type             = "gp3"
ebs_postgresql_size_in_gb   = 20
ebs_masking_size_in_gb      = 50
ebs_filesystem_type         = "xfs"
# ebs_snapshot_id           = "snap-0123456789abcdef0"
# ebs_iops                  = 3000
# ebs_throughput            = 125
# ebs_volume_initialization_rate = 250
# ebs_volume_tags           = { BackupClass = "predeploy" }
```

Important:
- Switching between `efs` and `ebs` changes how data is persisted and is not an in-place data migration.
- Plan a cutover/backup strategy before changing backend on an existing environment.
- For `ebs`, actual volume size is `max(ebs_postgresql_size_in_gb, ebs_masking_size_in_gb)`.
- For `ebs`, keep `desired_count = 1`; ECS creates one managed EBS volume per service task.
- Snapshot-based redeploy workflow: create a snapshot from the running task volume, then redeploy with `ebs_snapshot_id` set to that snapshot. See [EBS Snapshot Runbook](/Users/jonathanwilcox/Documents/projects/Work/Perforce/Delphix/Continuous_Compliance/containerized-masking/containerized_masking_ecs_tf/Local_Project_Docs/EBS_SNAPSHOT_RUNBOOK.md).

## JDBC TLS cert source automation (S3 / Secrets Manager)

This stack can optionally run an init-style sidecar to build the JDBC truststore before the app starts.

Set:
- `enable_jdbc_tls_init = true`
- Exactly one source:
  - `jdbc_tls_cert_source_s3_uri = "s3://<bucket>/<key>.pem"`
  - or `jdbc_tls_cert_source_secret_arn = "arn:aws:secretsmanager:...:secret:..."`
- Optional:
  - `jdbc_tls_init_image` (defaults to masking app image, but you should set this explicitly unless your app image already contains both `aws` CLI and `keytool`)
  - `jdbc_tls_truststore_password` (defaults to `changeit`)

Notes:
- Secret source must store PEM bundle text in `SecretString`.
- The task role gets source-read permissions automatically when this is enabled.
- The init image must contain both `aws` CLI and `keytool`.
- For S3 or Secrets Manager truststore automation, use a dedicated init image unless you have already verified the app image includes both tools.
- Both EBS and EFS modes expose customer cert material at `/var/delphix/ssl/`.
- Sidecar writes the truststore to `/var/delphix/ssl/.masking_certs`.
- The app container waits for sidecar `SUCCESS` before startup.
- A minimal sidecar image is provided at [docker/jdbc-tls-init/Dockerfile](/Users/jonathanwilcox/Documents/projects/Work/Perforce/Delphix/Continuous_Compliance/containerized-masking/containerized_masking_ecs_tf/docker/jdbc-tls-init/Dockerfile).

## Artifactory (non-ECR) registry instructions

Use this when your images live in Artifactory instead of ECR.

1. Create a read-only Docker token in Artifactory
   - Username: Artifactory user or service account
   - Password: API key or access token
   - Registry URL example: `artifactory.example.com/artifactory/<repo>/<image-prefix>`

2. Store credentials in AWS Secrets Manager (same region as ECS)

```json
{
  "username": "artifactory-user",
  "password": "artifactory-token-or-api-key"
}
```

Example:

```bash
aws secretsmanager create-secret \
  --name artifactory-registry-creds \
  --secret-string '{"username":"artifactory-user","password":"artifactory-token"}' \
  --region us-west-2
```

3. Set Terraform variables

```hcl
docker_registry_url               = "artifactory.example.com/artifactory/<repo>/<image-prefix>"
masking_database_image_tag        = "delphix-masking-database-29.0.0.1"
masking_app_image_tag             = "delphix-masking-app-29.0.0.1"
masking_proxy_image_tag           = "delphix-masking-proxy-29.0.0.1"
repository_credentials_secret_arn = "arn:aws:secretsmanager:us-west-2:123456789012:secret:artifactory-registry-creds-xxxx"
```

Notes:
- `docker_registry_url` includes the repo path but not the tag.
- ECS tasks in private subnets need outbound access to reach Artifactory (NAT or VPC endpoints).
- If the secret uses a customer-managed KMS key, the ECS execution role must be allowed to decrypt it.

## Quick start

1. Copy the example that matches your storage mode to `terraform.tfvars`
   - EFS-backed storage: `terraform.tfvars.efs.example`
   - EBS-backed storage: `terraform.tfvars.ebs.example`
2. Fill in registry/image values
3. Fill in ACM/Route53 values for HTTPS
4. Run:

```bash
terraform init
terraform plan
terraform apply
```

## Notes

- Based on [AWS ECS Fargate installation](https://help.delphix.com/cc/current/content/aws_ecs_fargate_installation.htm).
- ECS Fargate cannot directly mount arbitrary NFS exports; this stack uses EFS.
- If you need help getting your images into ECR, read [AWS ECR Upload Guide for Delphix Masking Images](uploading-images-to-ECR.md)
- If your registry is private and not ECR, set `repository_credentials_secret_arn`.
- The Java debug port (`15213`) is not exposed through ALB (it is not HTTP).
- For JDBC TLS certificate setup on ECS, see [JDBC TLS on ECS](/Users/jonathanwilcox/Documents/projects/Work/Perforce/Delphix/Continuous_Compliance/containerized-masking/containerized_masking_ecs_tf/Local_Project_Docs/JDBC_TLS_ECS.md).
- ECS Exec is enabled on the service and the task role includes the required `ssmmessages:*Channel` permissions.
- For ECS Exec in private subnets without NAT, add `ssm`, `ssmmessages`, and `ec2messages` interface endpoints or provide equivalent outbound access.
