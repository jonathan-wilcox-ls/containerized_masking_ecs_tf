# JDBC TLS Init Image

This image is intended for the `jdbc-truststore-init` ECS sidecar.

It contains:

- `aws` CLI for reading PEM bundles from S3 or Secrets Manager
- Java `keytool` from OpenJDK 17 for building `/var/delphix/ssl/.masking_certs`
- `/bin/sh` for the task-definition startup command

## Build

From the repo root:

```bash
docker build -t jdbc-tls-init:latest docker/jdbc-tls-init
```

## Push to ECR

Example for account `533267199142` in `us-east-1`:

```bash
aws ecr create-repository \
  --region us-east-1 \
  --repository-name jdbc-tls-init
```

```bash
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin 533267199142.dkr.ecr.us-east-1.amazonaws.com
```

```bash
docker tag jdbc-tls-init:latest 533267199142.dkr.ecr.us-east-1.amazonaws.com/jdbc-tls-init:latest
docker push 533267199142.dkr.ecr.us-east-1.amazonaws.com/jdbc-tls-init:latest
```

## Terraform

Set this in your tfvars after pushing:

```hcl
jdbc_tls_init_image = "533267199142.dkr.ecr.us-east-1.amazonaws.com/jdbc-tls-init:latest"
```

## Quick local check

```bash
docker run --rm jdbc-tls-init:latest /bin/sh -lc 'aws --version && keytool -help >/dev/null'
```
