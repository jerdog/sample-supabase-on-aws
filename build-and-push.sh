#!/bin/bash

# Build and push application service images to ECR
# Supported services: functions, kong, postgrest-lambda, tenant-manager, postgres-meta, studio

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read configuration from config.json (single source of truth)
CONFIG_FILE="$SCRIPT_DIR/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: config file not found: $CONFIG_FILE"
    exit 1
fi
AWS_ACCOUNT_ID=$(jq -r '.project.accountId' "$CONFIG_FILE")
AWS_REGION="${AWS_REGION:-$(jq -r '.project.region' "$CONFIG_FILE")}"

GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

echo "========================================="
echo "Application service image build and push tool"
echo "========================================="
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "AWS Region: $AWS_REGION"
echo "AWS Profile: ${AWS_PROFILE:-default}"
echo "Git SHA: $GIT_SHA"
echo "========================================="
echo ""

# All available services
ALL_SERVICES="functions kong postgrest-lambda tenant-manager postgres-meta studio function-deploy auth storage"

# Service config function: ECR repository name|build context directory|Dockerfile path
get_service_config() {
    local service="$1"
    case "$service" in
        functions)
            echo "functions-service|app/functions|Dockerfile"
            ;;
        kong)
            echo "kong-configured|app/kong|Dockerfile"
            ;;
        postgrest-lambda)
            echo "postgrest-lambda|app/postgrest-lambda|Dockerfile"
            ;;
        tenant-manager)
            echo "tenant-manager|app/tenant-manager|docker/Dockerfile"
            ;;
        postgres-meta)
            echo "postgres-meta|app/postgres-meta|Dockerfile"
            ;;
        studio)
            echo "studio|app/supabase|apps/studio/Dockerfile"
            ;;
        function-deploy)
            echo "function-deploy|app/function-deploy|apps/studio/Dockerfile"
            ;;
        auth)
            echo "auth-service|app/supabase-auth|Dockerfile"
            ;;
        storage)
            echo "storage|app/storage|Dockerfile"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Parse command-line arguments
SERVICE_TO_BUILD="$1"

# Determine which services to build
if [ -n "$SERVICE_TO_BUILD" ] && [ "$SERVICE_TO_BUILD" != "all" ]; then
    if [ -z "$(get_service_config "$SERVICE_TO_BUILD")" ]; then
        echo "Error: unknown service '$SERVICE_TO_BUILD'"
        echo "Available services: $ALL_SERVICES"
        exit 1
    fi
    echo "Building only service: $SERVICE_TO_BUILD"
    SERVICES_TO_BUILD="$SERVICE_TO_BUILD"
else
    echo "Building all services"
    SERVICES_TO_BUILD="$ALL_SERVICES"
fi
echo ""

# Switch to the project root directory (to ensure relative paths are correct)
cd "$SCRIPT_DIR"

# ECR login (private)
echo "Logging in to private ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
echo "Private ECR login succeeded"
echo ""

# Public ECR login (required for postgrest-lambda's base image)
echo "Logging in to AWS Public ECR..."
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
echo "Public ECR login succeeded"
echo ""

# Process each service
for service in $SERVICES_TO_BUILD; do
    echo "========================================="
    echo "Processing service: $service"
    echo "========================================="

    # Get the service config
    config=$(get_service_config "$service")
    if [ -z "$config" ]; then
        echo "Warning: unable to get service config"
        continue
    fi

    # Parse the config
    repository=$(echo "$config" | cut -d'|' -f1)
    context=$(echo "$config" | cut -d'|' -f2)
    dockerfile=$(echo "$config" | cut -d'|' -f3)

    echo "  Repository: $repository"
    echo "  Context: $context"
    echo "  Dockerfile: $context/$dockerfile"
    echo ""

    # Check whether the directory exists
    if [ ! -d "$context" ]; then
        echo "Warning: directory not found: $context, skipping this service"
        echo ""
        continue
    fi

    # Check whether the Dockerfile exists
    if [ ! -f "$context/$dockerfile" ]; then
        echo "Warning: Dockerfile not found: $context/$dockerfile, skipping this service"
        echo ""
        continue
    fi

    # Check whether the ECR repository exists
    echo "Checking ECR repository..."
    if ! aws ecr describe-repositories --repository-names "$repository" --region "$AWS_REGION" &> /dev/null; then
        echo "Repository does not exist, creating new repository: $repository"
        repo_uri=$(aws ecr create-repository \
            --repository-name "$repository" \
            --region "$AWS_REGION" \
            --image-scanning-configuration scanOnPush=true \
            --query 'repository.repositoryUri' \
            --output text)

        echo "  Repository URI: $repo_uri"

        # Set the lifecycle policy
        echo "  Setting lifecycle policy: keep the 10 most recent images"
        aws ecr put-lifecycle-policy \
            --repository-name "$repository" \
            --region "$AWS_REGION" \
            --lifecycle-policy-text '{
                "rules": [{
                    "rulePriority": 1,
                    "description": "Keep only 10 most recent images",
                    "selection": {
                        "tagStatus": "any",
                        "countType": "imageCountMoreThan",
                        "countNumber": 10
                    },
                    "action": {
                        "type": "expire"
                    }
                }]
            }' > /dev/null
    else
        echo "Repository already exists: $repository"
        repo_uri=$(aws ecr describe-repositories \
            --repository-names "$repository" \
            --region "$AWS_REGION" \
            --query 'repositories[0].repositoryUri' \
            --output text)
    fi
    echo ""

    # Build the image
    image_uri="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$repository:latest"
    echo "Building image (linux/amd64)..."
    echo "  Image URI: $image_uri"
    echo "  Building from: $context"
    echo ""

    # Copy RDS CA certificate to build context (required for SSL verification)
    CERT_FILE="$SCRIPT_DIR/certs/global-bundle.pem"
    if [ ! -f "$CERT_FILE" ]; then
        echo "Error: RDS CA certificate not found: $CERT_FILE"
        echo "Please download it: curl -o certs/global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"
        exit 1
    fi
    mkdir -p "$context/certs"
    cp "$CERT_FILE" "$context/certs/global-bundle.pem"

    if docker build --platform linux/amd64 -t "$repository:latest" -f "$context/$dockerfile" "$context"; then
        echo "Image build succeeded"
    else
        echo "Image build failed"
        exit 1
    fi
    echo ""

    # Tag the image
    echo "Tagging image..."
    docker tag "$repository:latest" "$image_uri"
    sha_image_uri="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$repository:$GIT_SHA"
    docker tag "$repository:latest" "$sha_image_uri"
    echo "Image tagging succeeded (latest + $GIT_SHA)"
    echo ""

    # Push the image
    echo "Pushing image to ECR..."
    if docker push "$image_uri" && docker push "$sha_image_uri"; then
        echo "Image push succeeded (latest + $GIT_SHA)"
    else
        echo "Image push failed"
        exit 1
    fi
    echo ""

    # Clean up RDS CA certificate from build context
    rm -rf "$context/certs"

    # Get the image digest
    image_digest=$(aws ecr describe-images \
        --repository-name "$repository" \
        --region "$AWS_REGION" \
        --image-ids imageTag=latest \
        --query 'imageDetails[0].imageDigest' \
        --output text 2>/dev/null || echo "unknown")

    echo "Service $service processing complete"
    echo "  Image URI: $image_uri"
    echo "  Image Digest: $image_digest"
    echo ""
done

echo "========================================="
echo "All images built and pushed successfully!"
echo "========================================="
echo ""

# List all images
echo "ECR image list:"
for service in $SERVICES_TO_BUILD; do
    config=$(get_service_config "$service")
    repository=$(echo "$config" | cut -d'|' -f1)

    echo ""
    echo "Repository: $repository"
    aws ecr describe-images \
        --repository-name "$repository" \
        --region "$AWS_REGION" \
        --query 'imageDetails[*].[imageTags[0],imagePushedAt,imageSizeInBytes]' \
        --output table 2>/dev/null || echo "  Repository is empty or does not exist"
done

echo ""
echo "========================================="
echo "Usage"
echo "========================================="
echo "Build all services:"
echo "  ./build-and-push.sh"
echo "  ./build-and-push.sh all"
echo ""
echo "Build a single service:"
echo "  ./build-and-push.sh functions"
echo "  ./build-and-push.sh kong"
echo "  ./build-and-push.sh postgrest-lambda"
echo "  ./build-and-push.sh tenant-manager"
echo ""
echo "Done!"
