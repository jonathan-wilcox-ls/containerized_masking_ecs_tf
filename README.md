# Delphix Masking on AWS ECS/Fargate (Terraform)

This folder is an ECS/Fargate variant of the existing Kubernetes deployment.

## What it deploys

- ECS cluster, task definition, and Fargate service
- Three containers in one task (`database`, `app`, `proxy`)
- ALB routing:
  - `/` -> proxy container on `8080`
- HTTPS via ACM (existing ARN or optional ACM+Route53 creation)
- EFS + access points for persistent directories:
  - `/var/delphix/postgresql`
  - `/var/delphix/masking`
- CloudWatch log group
- IAM roles for ECS execution/task + EFS

## Dev-friendly networking

By default, this stack can create a complete dev VPC (`create_dev_network = true`):

- 2 public subnets for ALB
- 2 private subnets for ECS/EFS
- Internet Gateway + NAT Gateway
- Route tables and associations

If you already have networking, set `create_dev_network = false` and provide:

- `vpc_id`
- `alb_subnet_ids`
- `ecs_subnet_ids`
- `efs_subnet_ids`

## HTTPS options

Use one of these:

1. Existing cert: set `certificate_arn`
2. New cert in Terraform: set all of:
   - `create_acm_certificate = true`
   - `acm_domain_name` (for example `masking-dev.example.com`)
   - `route53_zone_id`

## Required image inputs

- `docker_registry_url`
- `masking_database_image_tag`
- `masking_app_image_tag`
- `masking_proxy_image_tag`

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

## Quick start (dev)

1. Copy `terraform.tfvars.dev.example` to `terraform.tfvars`
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
