# Functions Service Deployment Guide

## 📋 Overview

This document explains how to build, package, and publish the Functions Service, and how to update the ECS Task.

## 🔧 Prerequisites

### 1. Environment Requirements

- Docker installed and running
- AWS CLI configured (profile: `<AWS_PROFILE>`)
- Push permissions to the ECR repository
- Update permissions for the ECS service

### 2. AWS Resource Information

```bash
AWS Account: <AWS_ACCOUNT_ID>
AWS Region: us-east-1
ECR Repository: functions-service
ECR URI: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/functions-service
ECS Cluster: <ECS_CLUSTER>
ECS Service: functions-service
```

### 3. Verify AWS Configuration

```bash
# Verify AWS configuration
aws sts get-caller-identity --profile <AWS_PROFILE>

# Expected output
# {
#     "UserId": "...",
#     "Account": "<AWS_ACCOUNT_ID>",
#     "Arn": "..."
# }
```

## 📦 Deployment Steps

### Method 1: Use the Unified Build Script (Recommended)

The project provides a unified build script that can automatically handle building and pushing.

#### 1. Use the Build Script

```bash
# Go to the project root directory
cd ~/supabase-on-aws

# Build and push the Functions Service
./app/build-and-push.sh functions
```

The script will automatically:
- Log in to ECR
- Build the Docker image (linux/amd64 platform)
- Push to ECR
- Display the latest image information

#### 2. Force Update the ECS Service

```bash
# Method A: Using AWS CLI
export AWS_PROFILE=<AWS_PROFILE>

aws ecs update-service \
  --cluster <ECS_CLUSTER> \
  --service functions-service \
  --force-new-deployment \
  --region us-east-1

# Method B: Redeploy using CDK
cd infra
cdk deploy SupabaseStack --require-approval never
```

#### 3. Monitor Deployment Status

```bash
# Check service status
aws ecs describe-services \
  --cluster <ECS_CLUSTER> \
  --services functions-service \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --query 'services[0].[serviceName,status,runningCount,desiredCount,deployments[0].rolloutState]' \
  --output table

# Expected output (after deployment completes)
# ----------------------------------------
# |         DescribeServices            |
# +--------------------+-------+---+---+
# |  functions-service | ACTIVE| 1 | 1 |
# |  COMPLETED         |       |   |   |
# +--------------------+-------+---+---+
```

### Method 2: Manual Build and Push

If you need finer-grained control, you can execute each step manually.

#### 1. Log in to ECR

```bash
export AWS_PROFILE=<AWS_PROFILE>
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=<AWS_ACCOUNT_ID>

# Log in to ECR
aws ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

#### 2. Build the Docker Image

```bash
# Go to the functions directory
cd ~/supabase-on-aws/app/functions

# Build the image (specifying linux/amd64 platform)
docker build --platform linux/amd64 -t functions-service:latest .

# Verify the image was created
docker images | grep functions-service
```

#### 3. Tag and Push the Image

```bash
# Tag the image
docker tag functions-service:latest \
  <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/functions-service:latest

# Push to ECR
docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/functions-service:latest
```

#### 4. Verify the Image Was Pushed

```bash
# View the image in the ECR repository
aws ecr describe-images \
  --repository-name functions-service \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --query 'sort_by(imageDetails,& imagePushedAt)[-1].[imageTags[0],imageDigest,imagePushedAt]' \
  --output table
```

#### 5. Update the ECS Service

```bash
# Force update the ECS Service (pull the latest image)
aws ecs update-service \
  --cluster <ECS_CLUSTER> \
  --service functions-service \
  --force-new-deployment \
  --region us-east-1 \
  --profile <AWS_PROFILE>
```

## 🔍 Deployment Verification

### 1. Check Task Status

```bash
# View running tasks
aws ecs list-tasks \
  --cluster <ECS_CLUSTER> \
  --service-name functions-service \
  --region us-east-1 \
  --profile <AWS_PROFILE>

# Get the Task ARN and view details
TASK_ARN=$(aws ecs list-tasks \
  --cluster <ECS_CLUSTER> \
  --service-name functions-service \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --query 'taskArns[0]' \
  --output text)

aws ecs describe-tasks \
  --cluster <ECS_CLUSTER> \
  --tasks $TASK_ARN \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --query 'tasks[0].[lastStatus,healthStatus,containers[0].image]' \
  --output table
```

### 2. Check Container Logs

```bash
# View logs from the last 10 minutes
aws logs tail /ecs/supabase \
  --since 10m \
  --filter-pattern "functions-service" \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --follow
```

### 3. Test API Endpoints

```bash
# Test health check
curl https://api.example.com/functions/health

# Expected response
# {
#   "status": "healthy",
#   "service": "Functions Service",
#   "timestamp": "2026-02-07..."
# }

# Test the Functions endpoint (with X-Project-ID header)
curl -H "X-Project-ID: test-project" \
  https://api.example.com/functions

# Expected response
# {
#   "service": "Functions Service",
#   "message": "Functions endpoint accessed successfully",
#   "project_id": "test-project",
#   "method": "GET",
#   "path": "/functions",
#   "timestamp": "2026-02-07..."
# }

# Test subdomain routing (recommended method - DNS already configured)
curl https://project-alpha.example.com/functions

# Expected response (project_id automatically extracted from subdomain)
# {
#   "message": "Functions endpoint accessed successfully",
#   "method": "GET",
#   "path": "/functions",
#   "project_id": "project-alpha",
#   "service": "Functions Service",
#   "timestamp": "2026-02-07 05:08:14.645021"
# }

# Test different project-ids
curl https://my-project-123.example.com/functions
curl https://test-app.example.com/functions

# Test subdomain routing + subpath
curl https://project-alpha.example.com/functions/hello-world

# Expected response (includes subpath)
# {
#   "message": "Functions endpoint accessed successfully",
#   "method": "GET",
#   "path": "/functions/hello-world",
#   "project_id": "project-alpha",
#   "service": "Functions Service",
#   "subpath": "hello-world",
#   "timestamp": "2026-02-07..."
# }

# Test POST request (subdomain routing)
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"function": "hello", "data": "test"}' \
  https://project-beta.example.com/functions/execute

# Expected response (includes request_data)
# {
#   "message": "Functions endpoint accessed successfully",
#   "method": "POST",
#   "path": "/functions/execute",
#   "project_id": "project-beta",
#   "request_data": {
#     "function": "hello",
#     "data": "test"
#   },
#   "service": "Functions Service",
#   "subpath": "execute",
#   "timestamp": "2026-02-07..."
# }
```

## 🐛 Troubleshooting

### Issue 1: Task Fails to Start

**Symptom**: The ECS Task remains stuck in PENDING or STOPPED state

**Troubleshooting Steps**:

```bash
# 1. Check the reason for Task failure
aws ecs describe-tasks \
  --cluster <ECS_CLUSTER> \
  --tasks $TASK_ARN \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --query 'tasks[0].stoppedReason'

# 2. Check container logs
aws logs tail /ecs/supabase \
  --since 30m \
  --filter-pattern "functions-service" \
  --region us-east-1 \
  --profile <AWS_PROFILE>
```

**Common Causes**:
- ECR image pull failure: check ECR permissions and whether the image exists
- Health check failure: confirm the application starts normally inside the container
- Insufficient resources: check ECS cluster capacity

### Issue 2: Health Check Failure

**Symptom**: The Task is terminated shortly after starting

**Troubleshooting Steps**:

```bash
# View health check configuration
aws ecs describe-task-definition \
  --task-definition functions-service \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --query 'taskDefinition.containerDefinitions[0].healthCheck'
```

**Solution**:
- Confirm the `/health` endpoint returns a 200 status code
- Check whether the application startup time exceeds the health check interval
- Check container logs to confirm the application is running normally

### Issue 3: Kong Cannot Route to the Functions Service

**Symptom**: API requests return 503 or time out

**Troubleshooting Steps**:

```bash
# 1. Check Service Discovery
aws servicediscovery list-services \
  --region us-east-1 \
  --profile <AWS_PROFILE>

# 2. Verify Kong can resolve functions-service.kong.local
# Enter the Kong container
KONG_TASK=$(aws ecs list-tasks \
  --cluster <ECS_CLUSTER> \
  --service-name kong-gateway \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --query 'taskArns[0]' \
  --output text)

# 3. Check Kong logs
aws logs tail /ecs/supabase \
  --since 10m \
  --filter-pattern "kong" \
  --region us-east-1 \
  --profile <AWS_PROFILE>
```

**Solution**:
- Confirm the Security Group allows Kong → Functions Service (port 8080)
- Restart the Kong service to reload the configuration
- Verify Service Discovery DNS records

### Issue 4: Code Update Not Taking Effect

**Symptom**: API behavior does not change after deployment

**Troubleshooting Steps**:

```bash
# 1. Verify the image in ECR is actually the latest
aws ecr describe-images \
  --repository-name functions-service \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --query 'sort_by(imageDetails,& imagePushedAt)[-1].[imagePushedAt,imageDigest]' \
  --output table

# 2. Check the image used by the Task
aws ecs describe-tasks \
  --cluster <ECS_CLUSTER> \
  --tasks $TASK_ARN \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --query 'tasks[0].containers[0].[image,imageDigest]' \
  --output table
```

**Solution**:
- Confirm the image was pushed successfully (check the push time)
- Force redeploy the ECS Service: `--force-new-deployment`
- Wait for the old Task to fully stop and the new Task to start

## 📊 Deployment Checklist

Use this checklist to ensure the deployment succeeded:

- [ ] Docker image built successfully
- [ ] Image successfully pushed to ECR
- [ ] The image digest in ECR has been updated
- [ ] ECS Service triggered a new deployment
- [ ] New Task started successfully
- [ ] Task health check passed
- [ ] Old Task has stopped
- [ ] Service status is ACTIVE
- [ ] RunningCount = DesiredCount
- [ ] Rollout State = COMPLETED
- [ ] `/health` endpoint returns 200
- [ ] `/functions` endpoint responds correctly (using X-Project-ID header)
- [ ] Subdomain routing works correctly (`curl https://project-alpha.example.com/functions`)
- [ ] project_id is correctly extracted from the subdomain
- [ ] No errors in container logs

## 🔄 Rollback Steps

If the new version has issues, you need to roll back to a previous version:

```bash
# 1. View previous image versions
aws ecr describe-images \
  --repository-name functions-service \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --query 'sort_by(imageDetails,& imagePushedAt)[-5:].[imagePushedAt,imageDigest]' \
  --output table

# 2. Tag the old version as latest
OLD_DIGEST="sha256:xxxxx"  # Obtained from above

aws ecr batch-get-image \
  --repository-name functions-service \
  --image-ids imageDigest=$OLD_DIGEST \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --query 'images[0].imageManifest' \
  --output text | \
aws ecr put-image \
  --repository-name functions-service \
  --image-tag latest \
  --image-manifest fileb:///dev/stdin \
  --region us-east-1 \
  --profile <AWS_PROFILE>

# 3. Force redeployment
aws ecs update-service \
  --cluster <ECS_CLUSTER> \
  --service functions-service \
  --force-new-deployment \
  --region us-east-1 \
  --profile <AWS_PROFILE>
```

## 📝 Development Workflow

### Local Development and Testing

```bash
# 1. Go to the functions directory
cd ~/supabase-on-aws/app/functions

# 2. Install dependencies
pip3 install -r requirements.txt

# 3. Run locally
python3 app.py

# 4. Test in another terminal
curl http://localhost:8080/health
curl -H "X-Project-ID: test" http://localhost:8080/functions
```

### Full Workflow After Code Changes

```bash
# 1. Modify the code
vim app.py

# 2. Test locally
python3 app.py &
sleep 2
curl http://localhost:8080/health
kill %1

# 3. Build and push the new image
cd ~/supabase-on-aws
./app/build-and-push.sh functions

# 4. Update the ECS Service
export AWS_PROFILE=<AWS_PROFILE>
aws ecs update-service \
  --cluster <ECS_CLUSTER> \
  --service functions-service \
  --force-new-deployment \
  --region us-east-1

# 5. Monitor the deployment
watch -n 5 'aws ecs describe-services \
  --cluster <ECS_CLUSTER> \
  --services functions-service \
  --region us-east-1 \
  --profile <AWS_PROFILE> \
  --query "services[0].[serviceName,runningCount,deployments[0].rolloutState]" \
  --output table'

# 6. Test the new version
curl https://api.example.com/functions/health

# Test subdomain routing (recommended)
curl https://project-alpha.example.com/functions

# Expect to see project_id: "project-alpha"

# 7. Commit the code
git add .
git commit -m "Update functions service"
git push
```

## 📚 Related Documentation

- [Functions Service README](./README.md) - Service functionality description
- [Kong Subdomain Routing Configuration](../kong/SUBDOMAIN_ROUTING.md) - Routing configuration details
- [API Testing Guide](/infra/API_TEST_GUIDE.md) - API testing methods
- [Build Script Description](../build-and-push.sh) - How to use the unified build script

## 🆘 Getting Help

If you encounter issues, please provide the following information:

1. **Error Description**: Specific error messages or abnormal behavior
2. **Deployment Logs**: CDK deployment output or AWS CLI command output
3. **Container Logs**:
   ```bash
   aws logs tail /ecs/supabase --since 30m \
     --filter-pattern "functions-service" \
     --region us-east-1 --profile <AWS_PROFILE>
   ```
4. **Task Status**:
   ```bash
   aws ecs describe-tasks --cluster <ECS_CLUSTER> \
     --tasks $TASK_ARN --region us-east-1 --profile <AWS_PROFILE>
   ```
5. **Image Information**:
   ```bash
   aws ecr describe-images --repository-name functions-service \
     --region us-east-1 --profile <AWS_PROFILE>
   ```

---

**Last Updated**: 2026-02-07
**Maintainer**: DevOps Team
**Version**: v1.0.0
