# AWS ECR Upload Guide for Delphix Masking Images

## Overview
You have downloaded a Docker image archive (`masking-docker-images-2026.1.0.0.tar.gz`, 1.4GB) containing three images that need to be uploaded to AWS Elastic Container Registry (ECR).

**Images in archive:**
- `delphix-masking-app:2026.1.0.0`
- `delphix-masking-proxy:2026.1.0.0`
- `delphix-masking-database:2026.1.0.0`

## Prerequisites
- Docker installed and running on your machine
- AWS CLI installed and configured with appropriate credentials
- AWS permissions to create ECR repositories and push images
- Sufficient disk space (~3GB free for extracting and retagging images)

## Step-by-Step Process

### 1. Load Images into Docker
First, load all three images from the tar.gz archive into your local Docker:

```bash
docker load -i masking-docker-images-2026.1.0.0.tar.gz
```

Verify the images loaded successfully:
```bash
docker images | grep delphix-masking
```

### 2. Set Up AWS ECR

**Login to AWS ECR:**
```bash
# Replace <region> with your AWS region (e.g., us-east-1)
# Replace <account-id> with your AWS account ID
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account-id>.dkr.ecr.<region>.amazonaws.com
```

**Create ECR repositories** (one for each image):
```bash
aws ecr create-repository --repository-name delphix-masking-app --region <region>
aws ecr create-repository --repository-name delphix-masking-proxy --region <region>
aws ecr create-repository --repository-name delphix-masking-database --region <region>
```

*Note: If repositories already exist, you'll get an error but can proceed to the next step.*

### 3. Tag Images for ECR

Tag each image with your ECR repository URIs:

```bash
# Set variables for convenience (update these values)
AWS_ACCOUNT_ID="<your-account-id>"
AWS_REGION="<your-region>"
VERSION="2026.1.0.0"

# Tag the app image
docker tag delphix-masking-app:${VERSION} \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/delphix-masking-app:${VERSION}

# Tag the proxy image
docker tag delphix-masking-proxy:${VERSION} \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/delphix-masking-proxy:${VERSION}

# Tag the database image
docker tag delphix-masking-database:${VERSION} \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/delphix-masking-database:${VERSION}
```

Optionally, also tag as `latest`:
```bash
docker tag delphix-masking-app:${VERSION} \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/delphix-masking-app:latest

docker tag delphix-masking-proxy:${VERSION} \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/delphix-masking-proxy:latest

docker tag delphix-masking-database:${VERSION} \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/delphix-masking-database:latest
```

### 4. Push Images to ECR

Push each image to ECR (this may take some time depending on your upload speed):

```bash
# Push app image
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/delphix-masking-app:${VERSION}

# Push proxy image
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/delphix-masking-proxy:${VERSION}

# Push database image
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/delphix-masking-database:${VERSION}
```

If you tagged `latest`, push those as well:
```bash
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/delphix-masking-app:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/delphix-masking-proxy:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/delphix-masking-database:latest
```

### 5. Verify Upload

Verify the images are in ECR:
```bash
aws ecr list-images --repository-name delphix-masking-app --region <region>
aws ecr list-images --repository-name delphix-masking-proxy --region <region>
aws ecr list-images --repository-name delphix-masking-database --region <region>
```

Or view them in the AWS Console:
- Navigate to: ECR → Repositories → Select each repository

## Complete Script

Here's a complete script you can customize and run:

```bash
#!/bin/bash
set -e

# Configuration - UPDATE THESE VALUES
AWS_ACCOUNT_ID="123456789012"  # Your AWS account ID
AWS_REGION="us-east-1"          # Your AWS region
IMAGE_FILE="masking-docker-images-2026.1.0.0.tar.gz"
VERSION="2026.1.0.0"

echo "=== Loading Docker images from archive ==="
docker load -i ${IMAGE_FILE}

echo "=== Logging into AWS ECR ==="
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

echo "=== Creating ECR repositories (if needed) ==="
for repo in delphix-masking-app delphix-masking-proxy delphix-masking-database; do
  aws ecr create-repository --repository-name ${repo} --region ${AWS_REGION} 2>/dev/null || \
    echo "Repository ${repo} already exists"
done

echo "=== Tagging images ==="
ECR_BASE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker tag delphix-masking-app:${VERSION} ${ECR_BASE}/delphix-masking-app:${VERSION}
docker tag delphix-masking-app:${VERSION} ${ECR_BASE}/delphix-masking-app:latest

docker tag delphix-masking-proxy:${VERSION} ${ECR_BASE}/delphix-masking-proxy:${VERSION}
docker tag delphix-masking-proxy:${VERSION} ${ECR_BASE}/delphix-masking-proxy:latest

docker tag delphix-masking-database:${VERSION} ${ECR_BASE}/delphix-masking-database:${VERSION}
docker tag delphix-masking-database:${VERSION} ${ECR_BASE}/delphix-masking-database:latest

echo "=== Pushing images to ECR ==="
docker push ${ECR_BASE}/delphix-masking-app:${VERSION}
docker push ${ECR_BASE}/delphix-masking-app:latest

docker push ${ECR_BASE}/delphix-masking-proxy:${VERSION}
docker push ${ECR_BASE}/delphix-masking-proxy:latest

docker push ${ECR_BASE}/delphix-masking-database:${VERSION}
docker push ${ECR_BASE}/delphix-masking-database:latest

echo "=== Verifying uploads ==="
aws ecr list-images --repository-name delphix-masking-app --region ${AWS_REGION}
aws ecr list-images --repository-name delphix-masking-proxy --region ${AWS_REGION}
aws ecr list-images --repository-name delphix-masking-database --region ${AWS_REGION}

echo "=== Upload complete! ==="
```

## Important Notes

1. **Image Layers**: Docker only uploads unique layers, so if images share layers, the upload will be faster than expected.

2. **Upload Time**: With a 1.4GB archive, expect the upload to take 10-30 minutes depending on your internet speed and layer deduplication.

3. **Lifecycle Policies**: Consider setting up lifecycle policies in ECR to automatically clean up old images.

4. **Image Scanning**: Enable image scanning in ECR for security vulnerability detection.

5. **Cleanup Local Images**: After successful upload, you can remove local images to free space:
   ```bash
   docker rmi delphix-masking-app:2026.1.0.0
   docker rmi delphix-masking-proxy:2026.1.0.0
   docker rmi delphix-masking-database:2026.1.0.0
   # Also remove ECR-tagged versions
   ```

## Troubleshooting

**"docker: command not found"**
- Install Docker Desktop or Docker Engine

**"AWS credentials not found"**
- Run `aws configure` to set up your credentials

**"AccessDeniedException"**
- Ensure your IAM user/role has these permissions:
  - `ecr:GetAuthorizationToken`
  - `ecr:CreateRepository`
  - `ecr:PutImage`
  - `ecr:InitiateLayerUpload`
  - `ecr:UploadLayerPart`
  - `ecr:CompleteLayerUpload`

**"Repository already exists"**
- This is fine, just proceed to pushing images

**Upload is very slow**
- Consider using AWS Direct Connect or uploading from an EC2 instance in the same region
