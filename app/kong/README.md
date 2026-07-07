# Kong Gateway Service

Kong API Gateway is configured in DB-less mode, using a declarative configuration file to manage routing.

## Service Information

- **Proxy port**: 8000
- **Admin API port**: 8001 (internal access only)
- **Configuration mode**: DB-less (declarative configuration)

## File Overview

- `kong.yml` - Kong declarative configuration file
- `Dockerfile` - Docker image build file
- `build-push.sh` - Script to build and push the image to ECR
- `README.md` - This file

## Kong Configuration (kong.yml)

The current configuration includes the following services and routes:

### hello-api service
- **Upstream URL**: http://hello-api.kong.local:8080
- **Route path**: /hello
- **Strip Path**: false (keep the full path)

### Configuration example
```yaml
_format_version: "3.0"
_transform: true

services:
  - name: hello-api
    url: http://hello-api.kong.local:8080
    routes:
      - name: hello-route
        paths:
          - /hello
        strip_path: false
```

## Adding a New Route

### 1. Edit kong.yml
```yaml
services:
  - name: your-service
    url: http://your-service.kong.local:8080
    routes:
      - name: your-route
        paths:
          - /api/your-path
        strip_path: true
```

### 2. Rebuild and push
```bash
./build-push.sh
```

### 3. Restart the Kong service
```bash
aws ecs update-service \
  --cluster kong-gateway-cluster \
  --service kong-gateway \
  --force-new-deployment \
  --region us-east-1
```

## Route Configuration Notes

### strip_path parameter
- `strip_path: true` - strips the route path when forwarding
  - Request: `/api/hello` → forwarded as: `/`
- `strip_path: false` - keeps the full path when forwarding
  - Request: `/hello` → forwarded as: `/hello`

### Example scenarios

#### Scenario 1: Upstream service has a root-path API
```yaml
services:
  - name: api-service
    url: http://api.example.com
    routes:
      - name: api-route
        paths:
          - /api
        strip_path: true
```
Request `/api/users` → forwarded to `http://api.example.com/users`

#### Scenario 2: Upstream service has a specific path
```yaml
services:
  - name: hello-api
    url: http://hello-api.kong.local:8080
    routes:
      - name: hello-route
        paths:
          - /hello
        strip_path: false
```
Request `/hello` → forwarded to `http://hello-api.kong.local:8080/hello`

## Local Testing

### Start Kong (using Docker)
```bash
docker run -d --name kong \
  -p 8000:8000 \
  -p 8001:8001 \
  -e "KONG_DATABASE=off" \
  -e "KONG_DECLARATIVE_CONFIG=/tmp/kong.yml" \
  -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
  -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
  -e "KONG_PROXY_ERROR_LOG=/dev/stderr" \
  -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" \
  -v $(pwd)/kong.yml:/tmp/kong.yml \
  kong:3.5
```

### Test the routes
```bash
# Test the hello-api route
curl http://localhost:8000/hello

# Check Kong status (Admin API has limited functionality in DB-less mode)
curl http://localhost:8001/status
```

## Build and Push

### Using the script
```bash
./build-push.sh
```

### Manual build
```bash
# Log in to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com

# Build the image
docker buildx build --platform linux/amd64 -t kong-configured:latest . --load

# Tag and push
docker tag kong-configured:latest <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/kong-configured:latest
docker push <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/kong-configured:latest
```

## Deploying to ECS

After pushing the new image, force a restart of the Kong service:

```bash
aws ecs update-service \
  --cluster kong-gateway-cluster \
  --service kong-gateway \
  --force-new-deployment \
  --region us-east-1
```

Wait about 1-2 minutes for the new configuration to take effect.

## Environment Variables

Kong uses the following environment variables (configured in the ECS Task Definition):

- `KONG_DATABASE=off` - enables DB-less mode
- `KONG_DECLARATIVE_CONFIG=/tmp/kong.yml` - configuration file path
- `KONG_PROXY_ACCESS_LOG=/dev/stdout` - Proxy access log
- `KONG_ADMIN_ACCESS_LOG=/dev/stdout` - Admin access log
- `KONG_PROXY_ERROR_LOG=/dev/stderr` - Proxy error log
- `KONG_ADMIN_ERROR_LOG=/dev/stderr` - Admin error log
- `KONG_ADMIN_LISTEN=0.0.0.0:8001` - Admin API listen address

## Troubleshooting

### View Kong logs
```bash
aws logs tail /ecs/kong-gateway --follow --region us-east-1
```

### Verify route configuration
In DB-less mode, routes cannot be queried through the Admin API, so it's recommended to:
1. Check the kong.yml syntax
2. Review the container startup logs
3. Test whether the actual routes work

### Common issues

**502 Bad Gateway**
- Check whether the upstream service is running normally
- Verify Service Discovery DNS resolution
- Confirm that Security Group rules allow Kong to access the upstream service

**404 Not Found**
- Check the route path configuration
- Verify the strip_path setting
- Confirm the actual endpoint path of the upstream service

## Kong Version

Currently using Kong 3.5.
