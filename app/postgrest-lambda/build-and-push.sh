#!/bin/bash
set -e

# Config - read region from config.json (consistent with the root build-and-push.sh)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config.json"
if [ -f "$CONFIG_FILE" ]; then
  AWS_REGION=$(jq -r '.project.region' "$CONFIG_FILE")
else
  AWS_REGION="${AWS_REGION:-us-east-1}"
fi
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO_NAME="postgrest-lambda"
IMAGE_TAG="v14.1-lambda"

echo "=========================================="
echo "Building PostgREST Lambda image"
echo "=========================================="
echo "AWS Account: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "ECR Repo: $ECR_REPO_NAME"
echo "Image Tag: $IMAGE_TAG"
echo ""

# Log in to AWS Public ECR
echo "🔐 Logging in to AWS Public ECR..."
aws ecr-public get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin public.ecr.aws

# Create the ECR repository if it doesn't exist
echo "📦 Creating ECR repository..."
aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION 2>/dev/null || \
aws ecr create-repository \
    --repository-name $ECR_REPO_NAME \
    --region $AWS_REGION \
    --image-scanning-configuration scanOnPush=true

# Log in to the private ECR
echo "🔐 Logging in to private ECR..."
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build the image (x86_64)
echo "🏗️  Building x86_64 image..."
docker build \
    --platform linux/amd64 \
    -t $ECR_REPO_NAME:$IMAGE_TAG \
    -t $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMAGE_TAG \
    -t $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:latest \
    .

# Push to ECR
echo "⬆️  Pushing image to ECR..."
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMAGE_TAG
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:latest

echo ""
echo "=========================================="
echo "✅ Image built and pushed successfully!"
echo "=========================================="
echo "Image URI:"
echo "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMAGE_TAG"
echo ""
echo "Use this image to create a Lambda function:"
echo "aws lambda create-function \\"
echo "  --function-name postgrest-api \\"
echo "  --package-type Image \\"
echo "  --code ImageUri=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMAGE_TAG \\"
echo "  --role arn:aws:iam::$AWS_ACCOUNT_ID:role/lambda-execution-role \\"
echo "  --timeout 30 \\"
echo "  --memory-size 512 \\"
echo "  --environment Variables='{PGRST_DB_URI=postgresql://...,PGRST_DB_SCHEMAS=public,PGRST_DB_ANON_ROLE=anon,PGRST_JWT_SECRET=your-secret}'"
