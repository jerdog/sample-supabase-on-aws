# Supabase-on-AWS Deployment Guide

> This document is an automated deployment guide that Claude Code can execute directly.
>
> Manual steps are limited to: providing deployment parameters, completing DNS validation, and configuring the DNS CNAME record.

---

## Deployment Parameters (to be provided by the user)

Confirm the following parameters before deployment:

| Parameter | Description | Example |
|------|------|------|
| `AWS_ACCOUNT_ID` | AWS account ID | `123456789012` |
| `AWS_REGION` | Target deployment region | `us-west-2` |
| `BASE_DOMAIN` | Domain name (you need DNS management access) | `supabase.example.com` |
| DNS provider | Cloudflare / Route53 / other | Cloudflare |

## Prerequisites

| Tool | Version required | Purpose |
|------|---------|------|
| AWS CLI | v2+ | AWS resource management |
| Node.js | v18+ | CDK compilation |
| Docker | v20+ | Image builds (requires linux/amd64 platform support) |
| AWS CDK | v2.100+ | Infrastructure deployment (`npm install -g aws-cdk` or via npx) |
| jq | v1.6+ | JSON processing |
| Python | v3.9+ | Running tests |
| pnpm | v10+ | function-deploy dependency management |

The AWS account must have `AdministratorAccess` permissions.

---

## Step 0: Clean up hardcoded information in CLAUDE.md (if any)

**Purpose**: Make sure `CLAUDE.md` doesn't contain hardcoded account IDs, domain names, security group IDs, etc. left over from a previous deployment environment.

Check for and replace the following with generic placeholders:
- AWS Account ID → `See config.json → project.accountId`
- Domain name → `See config.json → domain.baseDomain`
- ACM Certificate ARN → `See config.json → infraStack.certificate.arn`
- Security group ID (`sg-xxx`) → remove the ID column, keep the name and rule description
- Hardcoded account in ECR URI → `<account_id>.dkr.ecr.<region>.amazonaws.com/...`
- Hardcoded domain names in command examples → `<baseDomain>` placeholder

**Verify**: `grep -E '(old-account-id|old-domain)' CLAUDE.md` should return no matches.

---

## Step 1: Request an ACM certificate

```bash
aws acm request-certificate \
  --domain-name "*.${BASE_DOMAIN}" \
  --validation-method DNS \
  --region ${AWS_REGION}
```

Record the returned `CertificateArn`.

Get the DNS validation record:

```bash
aws acm describe-certificate \
  --certificate-arn <certificate ARN> \
  --region ${AWS_REGION} \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord'
```

**User action required**: add the returned CNAME validation record with your DNS provider, and wait for the certificate status to become `Issued`.

Verify:

```bash
aws acm describe-certificate \
  --certificate-arn <certificate ARN> \
  --region ${AWS_REGION} \
  --query 'Certificate.Status' \
  --output text
# Expected output: ISSUED
```

---

## Step 2: Create and edit config.json

### 2.1 Choose an environment template

The project provides two config templates; choose based on the target environment:

```bash
# Test environment
cp config.test.json config.json

# Production environment
cp config.production.json config.json
```

### 2.2 Test vs. production configuration comparison

The `project.environment` field in `config.json` (`test` or `production`) drives differences in infrastructure behavior:

| Setting | Test | Production | Description |
|--------|------|------------|------|
| **VPC** | | | |
| `infraStack.vpc.maxAzs` | 2 | 3 | Number of availability zones |
| `infraStack.vpc.natGateways` | 1 | 2 | NAT gateways (affects cross-AZ egress redundancy) |
| **RDS (management DB + Worker DB)** | | | |
| `rds.serverlessV2MinCapacity` | 0.5 | 1 | Minimum ACU (0.5 = can pause) |
| `rds.serverlessV2MaxCapacity` | 4 | 16 | Maximum ACU |
| `rds.readers` | 0 | 1 | Number of read replicas (0 = writer only) |
| `workerRds.serverlessV2MinCapacity` | 0.5 | 1 | Worker DB minimum ACU |
| `workerRds.serverlessV2MaxCapacity` | 4 | 16 | Worker DB maximum ACU |
| `workerRds.readers` | 0 | 1 | Worker DB read replica count |
| **Redis** | | | |
| `redis.nodeType` | `cache.t3.micro` | `cache.r6g.large` | Instance size |
| `redis.numCacheClusters` | 1 | 2 | Node count (2 = multi-AZ failover) |
| **ECS services** | | | |
| Kong | 512 CPU / 1024 MB / 1 instance | 2048 CPU / 4096 MB / 2 instances | Gateway layer |
| Tenant Manager | 512 / 1024 / 1 | 1024 / 2048 / 2 | Project management |
| Studio | 512 / 1024 / 1 | 1024 / 2048 / 2 | Admin UI |
| Functions | 512 / 1024 / 1 | 1024 / 2048 / 2 | Edge Functions |
| Function Deploy | 256 / 512 / 1 | 512 / 1024 / 2 | Function deployment |
| Postgres Meta | 256 / 512 / 1 | 512 / 1024 / 2 | Database metadata |
| Auth | 256 / 512 / 1 | 512 / 1024 / 2 | Auth service |
| **Data protection** | | | |
| RDS deletionProtection | `false` | `true` | Deletion protection |
| RDS removalPolicy | `DESTROY` | `RETAIN` | CDK removal policy |
| Backup retention | 7 days | 30 days | Automated backups |

**Estimated monthly cost** (us-east-1 reference):

| Resource | Test | Production |
|------|------|------------|
| VPC (NAT Gateway) | ~$35 | ~$70 |
| RDS (management + worker) | ~$90 | ~$450 |
| Redis | ~$15 | ~$300 |
| ECS Fargate (7 services) | ~$120 | ~$600 |
| ALB x 2 | ~$40 | ~$40 |
| **Total** | **~$300/month** | **~$1,460/month** |

### 2.3 Fill in the deployment parameters

Edit `config.json`, replacing the placeholders:

| Field | Set to |
|------|--------|
| `project.region` | `${AWS_REGION}` |
| `project.accountId` | `${AWS_ACCOUNT_ID}` |
| `infraStack.certificate.arn` | The certificate ARN obtained in Step 1 |
| `domain.baseDomain` | `${BASE_DOMAIN}` |
| `tags.DeploymentDate` | Current date (e.g. `2026-02-28`) |

The ECR repository address is automatically assembled from `accountId` + `region` in the build script, so no manual configuration is needed.

### 2.4 Switching environments

To switch from test to production (or vice versa):

```bash
# 1. Back up the current config
cp config.json config.$(jq -r '.project.environment' config.json).bak.json

# 2. Switch templates (keep your own accountId, region, certificate, domain)
TARGET=production  # or test
jq -s '.[0] * {
  project: {region: .[1].project.region, accountId: .[1].project.accountId, name: .[1].project.name},
  infraStack: {certificate: .[1].infraStack.certificate},
  domain: .[1].domain
}' config.${TARGET}.json config.json > config.new.json
mv config.new.json config.json

# 3. Redeploy
cd infra && npm run build && npx cdk deploy SupabaseStack --require-approval never

# 4. Force ECS to redeploy (a resource spec change requires restarting the tasks)
for svc in kong-gateway tenant-manager studio functions-service postgres-meta function-deploy auth-service; do
  aws ecs update-service --cluster infrastack-cluster --service "$svc" --force-new-deployment --region ${AWS_REGION}
done
```

> **Note**: Switching from test to production is a **non-destructive** upgrade (adds replicas, increases capacity). Switching from production to test will **reduce replicas** and lower the protection level, so make sure you've backed up your data first.

**Verify**:

```bash
jq '{env: .project.environment, region: .project.region, accountId: .project.accountId, certArn: .infraStack.certificate.arn, baseDomain: .domain.baseDomain}' config.json
```

---

## Step 3: CDK Bootstrap (first deployment only)

```bash
cd infra && npm install
npx cdk bootstrap aws://${AWS_ACCOUNT_ID}/${AWS_REGION}
```

**Verify**: the output includes `Environment aws://.../... bootstrapped`.

---

## Step 4: Build and push Docker images

### 4.1 Preprocessing: generate missing lockfiles

The build script requires a complete dependency lockfile in each service directory. The following two services need one generated ahead of time:

**tenant-manager** (needs `package-lock.json`):

```bash
cd app/tenant-manager
# If npm install reports an arborist error, clear the cache first
rm -rf node_modules /home/$USER/.npm/_cacache
npm install
cd ../..
```

**function-deploy** (needs `pnpm-lock.yaml`):

```bash
cd app/function-deploy
pnpm install --lockfile-only
cd ../..
```

> **Known issue**: npm 10.x can throw a `Cannot read properties of null (reading 'matches')` error in some environments; deleting `~/.npm/_cacache` resolves it.

### 4.2 Build all services

```bash
./build-and-push.sh
```

This builds 7 services: functions, kong, postgrest-lambda, tenant-manager, postgres-meta, studio, function-deploy.

The script automatically:
- Logs in to ECR (private + public)
- Creates any ECR repositories that don't exist yet (with a lifecycle policy: keep the 10 most recent images)
- Builds linux/amd64 images
- Pushes both the `latest` and `git-sha` tags

If a particular service fails to build, you can rebuild it individually:

```bash
./build-and-push.sh <service-name>
# Available service names: functions | kong | postgrest-lambda | tenant-manager | postgres-meta | studio | function-deploy
```

**Verify**:

```bash
aws ecr describe-repositories --region ${AWS_REGION} --query 'repositories[*].repositoryName' --output json
# Expected to include: functions-service, kong-configured, postgrest-lambda, tenant-manager, postgres-meta, studio, function-deploy
```

---

## Step 5: Deploy the infrastructure

```bash
cd infra
npm run build
npx cdk deploy SupabaseStack --require-approval never
```

Expect roughly **159 AWS resources** to be created, taking **10-15 minutes**.

Main resources created:
- VPC (2 AZs, 1 NAT Gateway)
- Aurora Serverless v2 × 2 (management cluster + worker cluster)
- ECS Fargate services × 7 (Kong, Tenant Manager, Studio, Functions, Function Deploy, Postgres Meta, Project Service)
- ALB × 2 (Kong ALB + Studio ALB)
- ElastiCache Redis (AUTH + TLS)
- EFS (Functions storage)
- WAF WebACL
- CloudWatch alarms
- Cloud Map service discovery

### 5.1 Set the ECR Lambda pull permission

After the CDK deployment finishes, you need to add a Lambda pull permission to the `postgrest-lambda` ECR repository; otherwise Lambda won't be able to pull the image when creating a project:

```bash
aws ecr set-repository-policy \
  --repository-name postgrest-lambda \
  --region ${AWS_REGION} \
  --policy-text '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "LambdaECRAccess",
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"],
      "Condition": {
        "StringLike": {
          "aws:sourceArn": "arn:aws:lambda:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':function:*"
        }
      }
    }]
  }'
```

> **Known issue**: the Lambda execution role created by CDK has ECR permissions, but the ECR repository policy does not allow the Lambda service to pull by default. Skipping this step causes a `Lambda does not have permission to access the ECR image` error when creating a project.

### 5.2 Record the deployment outputs

```bash
aws cloudformation describe-stacks \
  --stack-name SupabaseStack --region ${AWS_REGION} \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table
```

Key output values:

| Output key | Purpose |
|--------|------|
| `ALBDnsName` | Kong ALB DNS, the DNS CNAME target |
| `StudioALBDnsName` | Studio ALB DNS |
| `RdsEndpoint` | Management database endpoint |
| `WorkerRdsEndpoint` | Worker database endpoint |
| `RedisEndpoint` | Redis endpoint |
| `LambdaExecutionRoleArn` | Lambda execution role |
| `LambdaSgId` | Lambda security group |

---

## Step 6: Configure DNS

**User action required**: add a wildcard CNAME record with your DNS provider.

| Record name | Type | Value | Note |
|--------|------|---|------|
| `*.${BASE_DOMAIN}` | CNAME | `<ALBDnsName output value>` | Turn off CDN proxying (e.g. Cloudflare's grey-cloud mode) |

> **Note for Cloudflare users**:
> - Enter `*` as the record name (under the `${BASE_DOMAIN}` zone); Cloudflare will automatically append the domain suffix
> - **Proxying must be turned off** (DNS only / grey cloud), otherwise the ACM certificate's SNI matching will fail
> - If the domain is a multi-level subdomain (e.g. `supabase.example.com`), the record name should be `*.supabase` (under the `example.com` zone)

**Verify**:

```bash
nslookup test.${BASE_DOMAIN} 1.1.1.1
# Expected output: canonical name = <ALBDnsName>, resolving to the ALB's IP
```

---

## Step 7: Register the worker database and create the first project

```bash
./scripts/provision-worker-and-create-project.sh
```

The script automatically:
1. Retrieves the worker RDS endpoint and password from the CloudFormation outputs
2. Retrieves the Admin API key from Secrets Manager
3. Registers the worker RDS instance with Tenant Manager
4. Creates a test project (initializes the database schema, creates the PostgREST Lambda, registers a Kong consumer, generates API keys)

Example success output:
```
  Worker RDS:     supabase-worker-cluster.cluster-xxx.us-west-2.rds.amazonaws.com
  Instance ID:    supabase-worker-01
  Project Ref:    fd03vkjr73dptzl8bihy
```

**Verify**:

```bash
# Get the Studio ALB
STUDIO_ALB=$(aws cloudformation describe-stacks \
  --stack-name SupabaseStack --region ${AWS_REGION} \
  --query 'Stacks[0].Outputs[?OutputKey==`StudioALBDnsName`].OutputValue' \
  --output text)

# List projects
curl -sk "https://${STUDIO_ALB}/api/v1/projects" | jq '.[].ref'
```

---

## Step 8: Run the automated tests

```bash
cd tests
pip install -r requirements.txt
./RUN_TESTS.sh
```

Expected result: **34 passed, 3 skipped**.

Test coverage:

| Group | Test count | Content |
|----|--------|------|
| A: Project creation | 2 | Create a project via the Studio API |
| B: API keys | 2 | Fetch and validate opaque-format keys |
| C: SQL CRUD | 8 | Create/read/update/delete via the Studio SQL endpoint |
| D: Metadata | 2 | 9 metadata endpoints (tables, views, extensions, etc.) |
| E: Secrets | 3 (skipped) | Secrets management (not implemented) |
| F: Table CRUD | 8 | Full DDL + DML lifecycle |
| G: SDK CRUD + RLS | 8 | Supabase SDK operations + row-level security validation |
| H: Invalid keys | 4 | Random key, forged key, empty key, and no key all return 401 |

---

## Deployment verification checklist

Once all steps are complete, confirm each item:

- [ ] All ECS services show `runningCount == desiredCount`
  ```bash
  aws ecs describe-services --cluster infrastack-cluster \
    --services kong-gateway tenant-manager studio functions-service function-deploy postgres-meta \
    --region ${AWS_REGION} \
    --query 'services[*].[serviceName,runningCount,desiredCount]' --output table
  ```
- [ ] Automated tests show 34 passed, 3 skipped
- [ ] The SDK endpoint is reachable: `https://<project_ref>.${BASE_DOMAIN}/rest/v1/`

---

## Day-to-day operations

### Updating service code

```bash
# 1. Build and push the new image
./build-and-push.sh <service-name>

# 2. Force ECS to pull the new image
aws ecs update-service --cluster infrastack-cluster \
  --service <ECS-service-name> --force-new-deployment --region ${AWS_REGION}
```

| Build target | ECS service name |
|---------|-----------|
| kong | kong-gateway |
| tenant-manager | tenant-manager |
| studio | studio |
| functions | functions-service |
| function-deploy | function-deploy |
| postgres-meta | postgres-meta |

### Viewing logs

```bash
aws logs tail /ecs/supabase --since 10m --region ${AWS_REGION}
aws logs tail /ecs/supabase --since 5m --filter-pattern "tenant-manager" --region ${AWS_REGION}
```

### Updating the infrastructure

```bash
cd infra && npm run build
npx cdk diff SupabaseStack      # Preview the changes
npx cdk deploy SupabaseStack    # Apply the changes
```

---

## Known issues and solutions

### 1. tenant-manager build fails: missing package-lock.json

**Symptom**: `COPY package.json package-lock.json ./` reports `/package-lock.json: not found`

**Fix**: run `npm install` in the `app/tenant-manager/` directory to generate the lockfile. If you hit an npm arborist error, run `rm -rf ~/.npm/_cacache` first.

### 2. function-deploy build fails: missing pnpm-lock.yaml

**Symptom**: turbo prune reports `lockfile not found at /app/pnpm-lock.yaml`

**Fix**: run `pnpm install --lockfile-only` in the `app/function-deploy/` directory.

### 3. Creating a project reports an ECR permission error

**Symptom**: `Lambda does not have permission to access the ECR image`

**Fix**: run the `aws ecr set-repository-policy` command from step 5.1.

### 4. DNS isn't resolving (NXDOMAIN)

**Symptom**: `nslookup test.${BASE_DOMAIN}` returns NXDOMAIN

**Troubleshooting**:
- Check whether the Cloudflare record name is correct (multi-level subdomains need to be split, e.g. `*.supabase` under the `example.com` zone)
- Check whether you used the fully qualified domain name, causing the suffix to be appended twice
- DNS propagation can take a few minutes

### 5. Kong returns 401 Unauthorized

**Troubleshooting**:
1. Confirm you're using an opaque key (`sb_publishable_*` / `sb_secret_*`), not a JWT
2. The request must set both the `apikey` and `Authorization: Bearer` headers
3. Re-fetch the key: `curl -sk "https://${STUDIO_ALB}/api/v1/projects/${REF}/api-keys" | jq .`

### 6. Creating a project times out

**Note**: the first project creation takes 2-3 minutes (Lambda VPC ENI cold start); the Studio ALB idle timeout is set to 400 seconds, so it usually doesn't time out. If it does, check the Tenant Manager logs.

---

## Architecture reference

### Request flow (Gateway JWT minting)

```
Client (Supabase SDK)
  │  apikey: sb_publishable_xxx
  │  Authorization: Bearer sb_publishable_xxx
  ▼
Kong ALB (*.baseDomain:443)
  ▼
Kong Gateway (ECS Fargate)
  ├─ pre-function: subdomain → X-Project-ID
  ├─ key-auth: validates the opaque API key → identifies the consumer/role
  ├─ dynamic-lambda-router:
  │    1. Redis cache lookup (jwt_secret + lambda_url)
  │    2. Cache miss → GET tenant-manager /project/{id}/config
  │    3. Mint a short-lived JWT (5 minutes, HS256, role=anon|service_role)
  │    4. SigV4 signature → POST Lambda Function URL
  ▼
PostgREST Lambda → validates the JWT → SET LOCAL role → SQL + RLS
  ▼
Worker Aurora (tenant database)
```

### API key formats

| Type | Format | Kong consumer | RLS |
|------|------|------------|-----|
| Anon (public) | `sb_publishable_{32 chars}` | `{ref}--anon` | Constrained |
| Service Role (server-side) | `sb_secret_{32 chars}` | `{ref}--service_role` | Bypassed |

### Security notes

- **Never expose `sb_secret_*`** in client-side code or public repositories
- The anon key is safe to use client-side — it's constrained by RLS policies
- The short-lived JWT minted by Kong is valid for only 5 minutes, minimizing the replay window
- All RDS connections use SSL encryption

---

## Quick reference

```bash
# Build all images
./build-and-push.sh

# Deploy the infrastructure
cd infra && npm run build && npx cdk deploy SupabaseStack --require-approval never

# Initialize the first project
./scripts/provision-worker-and-create-project.sh

# Run the tests
cd tests && pip install -r requirements.txt && ./RUN_TESTS.sh

# Get API keys
curl -sk "https://${STUDIO_ALB}/api/v1/projects/${PROJECT_REF}/api-keys" | jq .

# SDK query
curl -sk -H "apikey: ${KEY}" -H "Authorization: Bearer ${KEY}" \
  "https://${PROJECT_REF}.${DOMAIN}/rest/v1/table?select=*" | jq .

# Check service status
aws ecs describe-services --cluster infrastack-cluster \
  --services kong-gateway tenant-manager studio functions-service function-deploy postgres-meta \
  --region ${AWS_REGION} --query 'services[*].[serviceName,runningCount,desiredCount]' --output table

# View logs
aws logs tail /ecs/supabase --since 10m --region ${AWS_REGION}
```
