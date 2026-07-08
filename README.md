# Supabase-on-AWS

Supabase on AWS provides a scalable and multi-tenant platform for running [Supabase](https://supabase.com) in your own AWS account. This project addresses the growing need for organizations to maintain full control over their database infrastructure, authentication, and API layer while leveraging Supabase's powerful open-source ecosystem for application development and deployment.

Built based on [Supabase](https://github.com/supabase/supabase) open-source project (version [0c35ed5](https://github.com/supabase/supabase/commit/0c35ed5)). If you encounter any issues, please submit a PR directly. Special thanks to all contributors involved in the project transformation.

Multi-tenant Supabase platform running on AWS, powered by ECS Fargate, Kong Gateway, Aurora PostgreSQL Serverless v2, and AWS CDK.

## Architecture

**Gateway JWT Minting** pattern: clients send opaque API keys (`sb_publishable_xxx` / `sb_secret_xxx`), Kong validates via key-auth, a custom Lua plugin mints short-lived JWTs (5min HS256), and PostgREST enforces Row-Level Security.

```
Client (Supabase SDK)
  |  apikey: sb_publishable_xxx
  |  Authorization: Bearer sb_publishable_xxx
  v
Kong ALB (*.baseDomain:443)
  v
Kong Gateway (ECS Fargate)
  +- pre-function: subdomain -> X-Project-ID
  +- key-auth: validate opaque API key -> identify consumer/role
  +- dynamic-lambda-router:
  |    1. Redis cache lookup (jwt_secret + lambda_url)
  |    2. Cache miss -> GET tenant-manager /project/{id}/config
  |    3. Mint short-lived JWT (5min, HS256, role=anon|service_role)
  |    4. SigV4 sign -> POST Lambda Function URL
  v
PostgREST Lambda -> validate JWT -> SET LOCAL role -> SQL + RLS
  v
Worker Aurora (tenant database)
```

## Services

| Service | Tech | Port | Source |
|---------|------|------|--------|
| Kong Gateway | Kong 3.5 + custom Lua plugins | 8000/8001 | `app/kong/` |
| Tenant Manager | TypeScript / Fastify | 3001 | `app/tenant-manager/` |
| Studio | Next.js (forked Supabase Studio) | 3000 | `app/supabase/apps/studio/` |
| Function Deploy | Next.js | 3000 | `app/function-deploy/` |
| Functions Service | Deno | 8080 | `app/functions/` |
| Auth (GoTrue) | Go | 9999 | `app/supabase-auth/` |
| Postgres Meta | Node.js | 8080 | `app/postgres-meta/` |
| PostgREST Lambda | PostgREST + Lambda Web Adapter | - | `app/postgrest-lambda/` |

## Infrastructure

| Resource | Test | Production |
|----------|------|------------|
| VPC (AZs / NAT GW) | 2 AZ / 1 NAT | 3 AZ / 2 NAT |
| Aurora Serverless v2 x 2 | 0.5-4 ACU, 0 readers | 1-16 ACU, 1+ readers |
| ElastiCache Redis 7.1 | cache.t3.micro, 1 node | cache.r6g.large, 2 nodes (multi-AZ) |
| ECS Fargate x 7 | minimal (256-512 CPU) | scaled (512-2048 CPU, 2 replicas) |
| RDS deletion protection | off | on |
| Backup retention | 7 days | 30 days |
| Estimated monthly cost | ~$300 | ~$1,460 |

## Prerequisites

| Tool | Version |
|------|---------|
| AWS CLI | v2+ |
| Node.js | v18+ |
| Docker | v20+ (linux/amd64 support) |
| AWS CDK | v2.100+ |
| jq | v1.6+ |
| Python | v3.9+ |
| pnpm | v10+ |

AWS account with `AdministratorAccess` permissions.

## Quick Start

### 1. Request ACM certificate

```bash
aws acm request-certificate \
  --domain-name "*.${BASE_DOMAIN}" \
  --validation-method DNS \
  --region ${AWS_REGION}
```

Complete DNS validation and wait for `ISSUED` status.

### 2. Configure

```bash
# Choose environment template
cp config.test.json config.json        # test
# cp config.production.json config.json  # production

# Edit config.json: fill in accountId, region, certificate ARN, domain
```

Key fields to update:

| Field | Value |
|-------|-------|
| `project.region` | Your AWS region |
| `project.accountId` | Your AWS account ID |
| `infraStack.certificate.arn` | ACM certificate ARN from step 1 |
| `domain.baseDomain` | Your base domain |
| `tags.DeploymentDate` | A real date (e.g. `2026-02-28`) -- the template ships with the placeholder `<deployment-date>`, and `cdk deploy` will fail with `Tag [DeploymentDate] contained invalid characters` if left as-is, since `<`/`>` aren't valid in AWS tag values |

### 3. Set environment

The remaining steps interpolate `${AWS_ACCOUNT_ID}`, `${AWS_REGION}`, and
`${BASE_DOMAIN}` — export them from `config.json` so nothing resolves empty
(an empty `${AWS_ACCOUNT_ID}/${AWS_REGION}` makes `cdk bootstrap` fail with
`UnresolvedAccount`):

```bash
export AWS_ACCOUNT_ID=$(jq -r .project.accountId config.json)
export AWS_REGION=$(jq -r .project.region config.json)
export BASE_DOMAIN=$(jq -r .domain.baseDomain config.json)
```

> **Behind a corporate TLS-inspection proxy?** If `aws` commands fail with
> `SSL validation failed ... self-signed certificate in certificate chain`,
> point both the AWS CLI and Node/CDK at your corporate CA bundle:
>
> ```bash
> aws configure set ca_bundle /path/to/corporate-ca-bundle.pem   # AWS CLI (Python)
> export NODE_EXTRA_CA_CERTS=/path/to/corporate-ca-bundle.pem     # Node / CDK
> ```

### 4. Bootstrap CDK (first time only)

```bash
cd infra && npm install
npx cdk bootstrap aws://${AWS_ACCOUNT_ID}/${AWS_REGION}
```

### 5. Build & push Docker images

```bash
# Generate lockfiles if missing (package-lock.json is gitignored by design;
# each service's Docker build does `npm ci` / `pnpm install --frozen-lockfile`
# and needs one present on disk first)
cd app/tenant-manager && npm install && cd ../..
cd app/postgres-meta && npm install && cd ../..
cd app/storage && npm install --ignore-scripts && cd ../..
cd app/supabase && pnpm install --lockfile-only && cd ../..
# app/function-deploy/pnpm-lock.yaml is a deliberate .gitignore exception --
# it's committed and already present. Do NOT regenerate it here: `pnpm install
# --frozen-lockfile` (in its Dockerfile) requires it to match exactly, and
# running `pnpm install` against it can silently re-resolve/drop dependencies.

# Download RDS CA certificate (required for SSL verification)
mkdir -p certs
curl -o certs/global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# Build all 8 services
./build-and-push.sh
```

### 6. Deploy infrastructure

```bash
cd infra && npm run build && npx cdk deploy SupabaseStack --require-approval never --outputs-file ../cdk-outputs.json
```

`--outputs-file` writes every `CfnOutput` (ALB DNS names, all 7 ECS service names, RDS/Redis/EFS
endpoints, Secrets Manager ARNs) to `cdk-outputs.json` at the repo root -- gitignored, since it's
specific to your deployment. Come back to it any time without re-querying CloudFormation:

```bash
cat cdk-outputs.json | jq .SupabaseStack
jq -r '.SupabaseStack.KongServiceName' cdk-outputs.json   # look up a single value
```

It's overwritten on every `cdk deploy`, so it always reflects your current stack -- if you tear
down and redeploy (see [Tearing Down / Starting Over](#tearing-down--starting-over)), just run
`cdk deploy` again and this file catches up automatically.

Then set ECR Lambda pull permissions:

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

### 7. Configure DNS

Add a wildcard CNAME record pointing `*.${BASE_DOMAIN}` to the Kong ALB DNS name (from CDK outputs).

> **Cloudflare users**: disable proxy (DNS only / grey cloud) -- otherwise ACM SNI matching will fail.

### 8. Create first project

Use the existing CDK-deployed Worker Aurora cluster:

```bash
./scripts/provision-worker-and-create-project.sh
```

### 9. Add more clusters and projects

`create-rds-and-project.sh` creates a **new Aurora Serverless v2 cluster**, registers it with the platform, and creates a project on it -- all in one command. Every parameter is auto-detected from CloudFormation outputs, `config.json`, and Secrets Manager.

```bash
# Pass a suffix to name the cluster (supabase-worker-<suffix>)
./scripts/create-rds-and-project.sh 02

# No argument = auto-generated timestamp suffix
./scripts/create-rds-and-project.sh
```

What the script does:

| Step | Action |
|------|--------|
| 1 | Create Aurora Serverless v2 cluster (`supabase-worker-<suffix>`) |
| 2 | Wait for cluster + writer instance to become available (~5-8 min) |
| 3 | Store credentials in Secrets Manager (`supabase/worker-rds/supabase-worker-<suffix>`) |
| 4 | Register the new instance with tenant-manager |
| 5 | Set ECR Lambda pull permissions (idempotent) |
| 6 | Create a project and verify it is `ACTIVE_HEALTHY` |

The script is **idempotent** -- re-running with the same suffix skips already-created resources.

Optional environment variable overrides:

| Variable | Default | Description |
|----------|---------|-------------|
| `REGION` | from `config.json` | AWS region |
| `CLUSTER_ID` | `supabase-worker-<suffix>` | Aurora cluster identifier |
| `WORKER_IDENTIFIER` | `worker-<suffix>` | Identifier in tenant-manager |
| `PROJECT_NAME` | `project-<suffix>` | Project name |
| `ENGINE_VERSION` | `16.8` | PostgreSQL version |
| `MIN_ACU` / `MAX_ACU` | `0.5` / `4` | Serverless v2 capacity range |

Full example with all parameters explicitly set:

```bash
REGION=us-west-2 \
CLUSTER_ID=supabase-worker-prod-a \
WORKER_IDENTIFIER=worker-prod-a \
PROJECT_NAME=my-saas-app \
ENGINE_VERSION=16.8 \
MIN_ACU=1 \
MAX_ACU=8 \
./scripts/create-rds-and-project.sh
```

This creates a cluster `supabase-worker-prod-a` with 1-8 ACU capacity, registers it as `worker-prod-a`, and creates a project named `my-saas-app` on it.

### 10. Run tests

```bash
cd tests && pip install -r requirements.txt && ./RUN_TESTS.sh all
```

Expected: **104 passed, 3 skipped** across 6 test suites.

| Suite | Tests | Coverage |
|-------|-------|----------|
| Studio API | 49 | Project CRUD, SQL, Table CRUD, SDK + RLS, Secrets, API key validation, REST API |
| Auth | 14 | Signup, login, token refresh, user management, logout |
| Authenticated RLS | 13 | Cross-user isolation, JWT tampering, RLS enforcement |
| Realtime | 1 passed, 3 skipped | WebSocket broadcast, presence, CDC |
| Tenant Isolation | 11 | Cross-project read/write/delete blocked |
| Edge Functions | 16 | Deploy, invoke, update, delete, secrets injection, cleanup |

All configuration is auto-detected from CloudFormation outputs and `config.json`. No manual editing required.

Run individual suites:

```bash
./RUN_TESTS.sh studio       # Studio Management API
./RUN_TESTS.sh auth         # Auth (GoTrue)
./RUN_TESTS.sh auth-rls     # Authenticated user RLS
./RUN_TESTS.sh realtime     # Realtime WebSocket
./RUN_TESTS.sh isolation    # Tenant isolation
./RUN_TESTS.sh functions    # Edge Functions lifecycle
./RUN_TESTS.sh all          # All suites
```

Optional environment variable overrides (all auto-detected if not set):

| Variable | Description |
|----------|-------------|
| `REGION` | AWS region (from `config.json`) |
| `STACK_NAME` | CloudFormation stack name (default: `SupabaseStack`) |
| `PROJECT_REF` | Existing project ref (skip creation) |
| `KEEP_PROJECT=1` | Keep test project after tests complete |

## Common Commands

```bash
# Build single service
./build-and-push.sh <service>
# Services: functions | kong | postgrest-lambda | tenant-manager
#           postgres-meta | studio | function-deploy | auth

# Deploy infrastructure changes
cd infra && npm run build && npx cdk deploy SupabaseStack --require-approval never

# Force ECS redeployment
aws ecs update-service --cluster infrastack-cluster --service <service-name> \
  --force-new-deployment --region ${AWS_REGION}

# Check service status
aws ecs describe-services --cluster infrastack-cluster \
  --services kong-gateway tenant-manager studio functions-service \
          function-deploy postgres-meta auth-service \
  --region ${AWS_REGION} \
  --query 'services[*].[serviceName,runningCount,desiredCount]' --output table

# View logs
aws logs tail /ecs/supabase --since 10m --region ${AWS_REGION}

# Run specific test suite
cd tests && ./RUN_TESTS.sh auth       # Auth tests
cd tests && ./RUN_TESTS.sh isolation   # Tenant isolation tests
cd tests && ./RUN_TESTS.sh all         # All suites
```

## Tearing Down / Starting Over

What to tear down depends on how far you got. Check what's actually deployed first:

```bash
aws cloudformation list-stacks --region ${AWS_REGION} \
  --query 'StackSummaries[?StackStatus!=`DELETE_COMPLETE`].[StackName,StackStatus]' --output table
```

### If `SupabaseStack` failed and rolled back (most common)

CloudFormation deletes a stack automatically by default when `CREATE_FAILED` rolls back, so if the
list above shows only `CDKToolkit`, there's nothing to tear down -- fix whatever caused the failure
and just re-run:

```bash
cd infra && npm run build && npx cdk deploy SupabaseStack --require-approval never
```

### If `SupabaseStack` is actually running and you want it gone

```bash
cd infra && npx cdk destroy SupabaseStack
```

CDK only tracks resources it created. Any **extra** Aurora clusters added via
`./scripts/create-rds-and-project.sh` (step 9) are not part of the stack and won't be touched --
delete those separately if you created any:

```bash
aws rds describe-db-clusters --region ${AWS_REGION} --query 'DBClusters[*].DBClusterIdentifier' --output table
aws rds delete-db-cluster --db-cluster-identifier <cluster-id> --skip-final-snapshot --region ${AWS_REGION}
```

### Full clean slate (rebuild and redeploy everything from zero)

Deletes your built images and the CDK bootstrap, so the next `build-and-push.sh` / `cdk bootstrap`
starts completely fresh. **Does not** touch the ACM certificate -- keep it unless you're changing
domains, since re-requesting means redoing DNS validation.

```bash
# 1. Delete the service ECR repositories (irreversible -- deletes all pushed images)
for repo in kong-configured tenant-manager postgres-meta storage functions-service \
            studio function-deploy auth-service postgrest-lambda; do
  aws ecr delete-repository --repository-name "$repo" --region ${AWS_REGION} --force
done

# 2. Empty the CDK staging bucket -- it has versioning enabled, so a plain empty won't
#    remove old versions/delete-markers, which would otherwise block deletion
BUCKET="cdk-hnb659fds-assets-${AWS_ACCOUNT_ID}-${AWS_REGION}"
aws s3api list-object-versions --bucket "$BUCKET" --output json \
  | jq -r '(.Versions // [])[] , (.DeleteMarkers // [])[] | "\(.Key)\t\(.VersionId)"' \
  | while IFS=$'\t' read -r key vid; do
      aws s3api delete-object --bucket "$BUCKET" --key "$key" --version-id "$vid"
    done

# 3. Destroy the CDKToolkit bootstrap stack
aws cloudformation delete-stack --stack-name CDKToolkit --region ${AWS_REGION}
aws cloudformation wait stack-delete-complete --stack-name CDKToolkit --region ${AWS_REGION}

# 4. The staging bucket has a Retain deletion policy, so it survives step 3 -- it must be
#    deleted manually or the next bootstrap will collide with the (now-orphaned) bucket name
aws s3api delete-bucket --bucket "$BUCKET" --region ${AWS_REGION}

# 5. Re-bootstrap
cd infra && npx cdk bootstrap aws://${AWS_ACCOUNT_ID}/${AWS_REGION}
```

Then continue from [step 5 (Build & push Docker images)](#5-build--push-docker-images).

## API Key Format

| Type | Format | Kong Consumer | RLS |
|------|--------|---------------|-----|
| Anon (public) | `sb_publishable_{32chars}` | `{ref}--anon` | enforced |
| Service Role (server-side) | `sb_secret_{32chars}` | `{ref}--service_role` | bypassed |

**Never expose `sb_secret_*` keys in client-side code or public repositories.**

## Project Structure

```
├── app/
│   ├── kong/                  # Kong Gateway + custom Lua plugins
│   ├── tenant-manager/        # Project management API (Fastify)
│   ├── supabase/              # Forked Supabase Studio (Next.js)
│   ├── function-deploy/       # Edge Functions management (Next.js)
│   ├── functions/             # Edge Functions runtime (Deno)
│   ├── supabase-auth/         # GoTrue auth service
│   ├── postgres-meta/         # Database metadata API
│   └── postgrest-lambda/      # PostgREST on Lambda
├── infra/                     # AWS CDK infrastructure
│   └── lib/supabase-stack.ts  # Main CDK stack
├── tests/                     # Automated test suites
├── scripts/                   # Provisioning scripts
├── certs/                     # RDS CA certificate bundle
├── config.test.json           # Test environment template
├── config.production.json     # Production environment template
└── build-and-push.sh          # Docker build & ECR push script
```

## Known Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| Missing package-lock.json | tenant-manager build fails: `not found` | Run `npm install` in `app/tenant-manager/` |
| ECR Lambda permission | `Lambda does not have permission to access the ECR image` | Run `aws ecr set-repository-policy` (see step 6). Note this policy is lost if the `postgrest-lambda` ECR repo is ever deleted/recreated (e.g. a full teardown) -- it must be reapplied |
| Lambda image manifest error | `The image manifest, config or layer media type ... is not supported` creating a project | Docker's default build behavior attaches an OCI provenance/SBOM attestation index, which Lambda rejects. `build-and-push.sh` already builds with `--provenance=false --sbom=false`; if you built `postgrest-lambda` some other way, rebuild it with those flags and re-push |
| Kong 401 | Unauthorized on REST API calls | Use opaque keys (`sb_publishable_*`), not JWT. Set both `apikey` and `Authorization` headers |
| DNS NXDOMAIN | Domain not resolving | Check CNAME target, disable Cloudflare proxy, wait for propagation |
| Go build timeout / TLS handshake failure | auth-service Docker build hangs, or `tls: handshake failure` fetching modules | `app/supabase-auth/Dockerfile` pins `GOPROXY`. Corporate networks sometimes block/intercept one of `proxy.golang.org` (official) or `goproxy.cn` (China-region mirror) but not the other -- switch `ENV GOPROXY=...` in the Dockerfile to whichever proxy your network actually allows |
| AWS CLI SSL error | `SSL validation failed ... self-signed certificate in certificate chain` | Behind a TLS-inspection proxy: `aws configure set ca_bundle <path>` and `export NODE_EXTRA_CA_CERTS=<path>` (see step 3) |

## Security

All database connections use SSL with certificate verification (`verify-ca` mode) against the AWS RDS global CA bundle.

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This project is licensed under the Apache-2.0 License.
