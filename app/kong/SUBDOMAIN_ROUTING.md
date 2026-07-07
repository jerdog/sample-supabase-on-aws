# Subdomain Routing Configuration (Subdomain Routing)

## 📋 Feature Overview

Kong Gateway now supports automatically extracting the `project-id` from the subdomain, setting it as the `X-Project-ID` header, and forwarding it to the backend service.

## 🎯 Use Cases

### 1. Accessing the Functions service via subdomain

**Access method**:
```
https://project-alpha.example.com/functions
```

**Behavior**:
- Kong extracts `project-alpha` from the subdomain
- Automatically sets the header: `X-Project-ID: project-alpha`
- Forwards to `functions-service.kong.local:8080/functions`
- The Functions service receives `X-Project-ID: project-alpha`

### 2. Accessing via the main domain + header

**Access method**:
```bash
curl -H "X-Project-ID: project-alpha" \
  https://api.example.com/functions
```

**Behavior**:
- Kong detects that the `X-Project-ID` header already exists
- Forwards the header directly to the backend service
- The Functions service receives `X-Project-ID: project-alpha`

## 🔧 Technical Implementation

### Kong configuration

**File**: `/app/kong/kong.yml`

```yaml
services:
  - name: functions-service
    url: http://functions-service.kong.local:8080
    routes:
      - name: functions-route
        paths:
          - /functions
        strip_path: false
        # Matches all *.example.com subdomains
        hosts:
          - "*.example.com"
          - "api.example.com"
    plugins:
      # 1. CORS support
      - name: cors
        config:
          origins: ["*"]
          methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]

      # 2. Extract project-id from the subdomain
      - name: pre-function
        config:
          access:
            - |
              local host = kong.request.get_header("Host")
              local project_id = kong.request.get_header("X-Project-ID")

              if not project_id and host then
                local subdomain = host:match("^([^%.]+)%.example%.com")

                if subdomain and subdomain ~= "api" then
                  kong.service.request.set_header("X-Project-ID", subdomain)
                  kong.log.info("Extracted project-id: ", subdomain)
                end
              elseif project_id then
                kong.service.request.set_header("X-Project-ID", project_id)
              end
```

### Extraction logic

1. **Check the X-Project-ID header**:
   - If it already exists, forward it directly

2. **Extract from the Host header**:
   - Match pattern: `([^%.]+)%.example%.com`
   - Extract the first subdomain segment

3. **Special handling**:
   - `api.example.com`: does not extract a project-id (keeps the original header)
   - Other subdomains: extracted as the project-id

## 📝 Usage Examples

### Example 1: Access via subdomain

```bash
# Request
curl https://my-project.example.com/functions

# Kong processing
# 1. Extracts "my-project" from Host: my-project.example.com
# 2. Sets X-Project-ID: my-project
# 3. Forwards to functions-service

# Functions service receives
# GET /functions
# Headers: X-Project-ID: my-project

# Response
{
  "service": "Functions Service",
  "project_id": "my-project",
  "message": "Functions endpoint accessed successfully",
  "method": "GET",
  "path": "/functions"
}
```

### Example 2: Subdomain + subpath

```bash
# Request
curl https://project-alpha.example.com/functions/hello-world

# Kong processing
# Extracted: project-alpha
# Path: /functions/hello-world (unchanged)

# Response
{
  "service": "Functions Service",
  "project_id": "project-alpha",
  "method": "GET",
  "path": "/functions/hello-world",
  "subpath": "hello-world"
}
```

### Example 3: POST request

```bash
# Request
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"name": "test", "value": 123}' \
  https://project-beta.example.com/functions/execute

# Response
{
  "service": "Functions Service",
  "project_id": "project-beta",
  "method": "POST",
  "path": "/functions/execute",
  "subpath": "execute",
  "request_data": {
    "name": "test",
    "value": 123
  }
}
```

### Example 4: Main domain + header

```bash
# Request
curl -H "X-Project-ID: custom-project" \
  https://api.example.com/functions

# Kong processing
# Detects that the X-Project-ID header already exists
# Forwards it directly

# Response
{
  "service": "Functions Service",
  "project_id": "custom-project",
  "method": "GET",
  "path": "/functions"
}
```

## 🔍 Verification and Debugging

### 1. View Kong logs

```bash
# View Kong logs
aws logs tail /ecs/supabase --since 10m \
  --filter-pattern "Extracted project-id" \
  --region us-east-1 \
  --profile <AWS_PROFILE>
```

**Expected output**:
```
Extracted project-id from subdomain: project-alpha
Using existing X-Project-ID: custom-project
```

### 2. Test different subdomains

```bash
# Test 1: Simple project name
curl https://test.example.com/functions

# Test 2: Project name with a hyphen
curl https://my-project-123.example.com/functions

# Test 3: Numeric-only project name
curl https://12345.example.com/functions

# Test 4: API domain (should not extract a project-id)
curl https://api.example.com/functions
# Expected: no project_id, or it shows as null
```

### 3. Verify the Functions service receives it

```bash
# View Functions service logs
aws logs tail /ecs/supabase --since 5m \
  --filter-pattern "functions-service" \
  --region us-east-1 \
  --profile <AWS_PROFILE>
```

## 🌐 DNS Configuration Requirements

For subdomain routing to work, DNS must be configured as follows:

### Wildcard DNS resolution

**DNS record**:
```
Type: CNAME
Name: *.example.com
Value: <ALB_DNS_NAME>
TTL: 300
```

**Notes**:
- The wildcard `*` matches all subdomains
- All subdomains resolve to the same ALB
- Kong routes to different services based on the Host header

### Test DNS resolution

```bash
# Test wildcard resolution
nslookup test-project.example.com
nslookup my-app.example.com
nslookup any-subdomain.example.com

# Expected: all subdomains resolve to the ALB IP
```

## 📊 Route Priority

Kong's route matching priority (from highest to lowest):

1. **Exact match**: precise host + path combination
2. **Regex match**: routes with a higher regex_priority
3. **Wildcard match**: `*.example.com`

Current configuration:
- `/functions` path + `*.example.com` host
- Any subdomain accessing `/functions` will match this route

## 🔒 Security Considerations

### 1. Project ID validation

It is recommended to validate the project-id in the Functions service:

```python
@app.route('/functions')
def functions():
    project_id = request.headers.get('X-Project-ID')

    # Validate the project-id format
    if not project_id or not is_valid_project_id(project_id):
        return jsonify({"error": "Invalid or missing project ID"}), 400

    # Verify the project-id exists
    if not project_exists(project_id):
        return jsonify({"error": "Project not found"}), 404

    # Handle the request
    return process_request(project_id)
```

### 2. Rate limiting

It is recommended to set independent rate limits for different project-ids:

```yaml
# Kong configuration
plugins:
  - name: rate-limiting
    config:
      minute: 100
      policy: local
      header_name: X-Project-ID
```

### 3. Access control

Access control can be implemented based on project-id:

```lua
-- Kong pre-function
local project_id = kong.request.get_header("X-Project-ID")
local allowed_projects = {"project-alpha", "project-beta"}

if not contains(allowed_projects, project_id) then
  return kong.response.exit(403, {error = "Project not allowed"})
end
```

## 🚀 Deployment Steps

1. ✅ **Update Kong configuration** (`kong.yml`)
2. ✅ **Rebuild the Kong image**
   ```bash
   ./build-and-push.sh kong
   ```

3. ✅ **Deploy to ECS**
   ```bash
   cd ../infra
   cdk deploy SupabaseStack
   ```

4. ⏳ **Configure wildcard DNS resolution**
   - Add a `*.example.com` CNAME record
   - Point it to the ALB DNS

5. ⏳ **Test and verify**
   ```bash
   curl https://test-project.example.com/functions
   ```

## 📚 Related Documentation

- [Functions Service README](/app/functions/README.md)
- [Kong Gateway Configuration](/app/kong/kong.yml)
- [API Test Guide](/infra/API_TEST_GUIDE.md)

---

**Last updated**: 2026-02-07
**Kong version**: 3.5
**Configuration file**: `/app/kong/kong.yml`
