# Supabase-on-AWS Complete Architecture Diagrams

> This document showcases the architecture design of the Supabase-on-AWS project from multiple perspectives in detail

## Table of Contents
1. [Overall System Architecture](#1-overall-system-architecture)
2. [Network and Infrastructure Architecture](#2-network-and-infrastructure-architecture)
3. [Request Flow Architecture](#3-request-flow-architecture-gateway-jwt-minting)
4. [Data Flow Architecture](#4-data-flow-architecture)
5. [Service Component Architecture](#5-service-component-architecture)
6. [Security Architecture](#6-security-architecture)
7. [Deployment Architecture](#7-deployment-architecture)

---

## 1. Overall System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Supabase-on-AWS Platform                            │
│                         Multi-Tenant SaaS Architecture                       │
└─────────────────────────────────────────────────────────────────────────────┘

                                    Internet
                                       │
                                       ▼
                    ┌──────────────────────────────────┐
                    │   Route 53 DNS                   │
                    │   *.example.com               │
                    │   - api.example.com           │
                    │   - studio.example.com        │
                    │   - {project}.example.com     │
                    └──────────────────────────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud (us-east-1)                            │
│  Account: <AWS_ACCOUNT_ID>                                                        │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        Application Load Balancers                    │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │    │
│  │  │  Kong ALB    │  │ Studio ALB   │  │ Tenant Mgr   │              │    │
│  │  │  (API GW)    │  │              │  │    ALB       │              │    │
│  │  │  Port 443    │  │  Port 443    │  │  Port 443    │              │    │
│  │  │  ACM Cert    │  │  ACM Cert    │  │  ACM Cert    │              │    │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │    │
│  └─────────┼──────────────────┼──────────────────┼──────────────────────┘    │
│            │                  │                  │                           │
│  ┌─────────┼──────────────────┼──────────────────┼──────────────────────┐    │
│  │         │      VPC (2 AZs, 1 NAT Gateway)     │                      │    │
│  │         │                  │                  │                      │    │
│  │  ┌──────▼──────────────────▼──────────────────▼──────────────────┐  │    │
│  │  │              ECS Fargate Cluster (<ECS_CLUSTER>)         │  │    │
│  │  │                                                                │  │    │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │  │    │
│  │  │  │   Kong      │  │   Studio    │  │   Tenant    │           │  │    │
│  │  │  │  Gateway    │  │   Service   │  │   Manager   │           │  │    │
│  │  │  │  (DB Mode)  │  │             │  │             │           │  │    │
│  │  │  │  512CPU     │  │  512CPU     │  │  512CPU     │           │  │    │
│  │  │  │  1024MB     │  │  1024MB     │  │  1024MB     │           │  │    │
│  │  │  └─────┬───────┘  └─────┬───────┘  └─────┬───────┘           │  │    │
│  │  │        │                 │                 │                   │  │    │
│  │  │  ┌─────▼─────────────────▼─────────────────▼───────┐          │  │    │
│  │  │  │         Functions Service (Edge Functions)      │          │  │    │
│  │  │  │         256CPU / 512MB                           │          │  │    │
│  │  │  └──────────────────────────────────────────────────┘          │  │    │
│  │  └────────────────────────────────────────────────────────────────┘  │    │
│  │                                                                       │    │
│  │  ┌────────────────────────────────────────────────────────────────┐  │    │
│  │  │              Lambda Functions (Per-Tenant)                     │  │    │
│  │  │                                                                │  │    │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │  │    │
│  │  │  │  PostgREST   │  │  PostgREST   │  │  PostgREST   │        │  │    │
│  │  │  │  Lambda      │  │  Lambda      │  │  Lambda      │        │  │    │
│  │  │  │  (Project-A) │  │  (Project-B) │  │  (Project-N) │        │  │    │
│  │  │  │  512MB       │  │  512MB       │  │  512MB       │        │  │    │
│  │  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │  │    │
│  │  └─────────┼──────────────────┼──────────────────┼───────────────┘  │    │
│  │            │                  │                  │                  │    │
│  │  ┌─────────┼──────────────────┼──────────────────┼───────────────┐  │    │
│  │  │         │      Data Layer                     │               │  │    │
│  │  │         │                                     │               │  │    │
│  │  │  ┌──────▼──────────────────────────────────────▼──────────┐   │  │    │
│  │  │  │         RDS PostgreSQL (Primary Instance)             │   │  │    │
│  │  │  │         db.t3.micro / PostgreSQL 16.6                 │   │  │    │
│  │  │  │                                                        │   │  │    │
│  │  │  │  ┌──────────────┐  ┌──────────────┐                  │   │  │    │
│  │  │  │  │  kong DB     │  │  supabase_   │                  │   │  │    │
│  │  │  │  │  (Kong       │  │  platform    │                  │   │  │    │
│  │  │  │  │   Config)    │  │  (Projects)  │                  │   │  │    │
│  │  │  │  └──────────────┘  └──────────────┘                  │   │  │    │
│  │  │  └───────────────────────────────────────────────────────┘   │  │    │
│  │  │                                                               │  │    │
│  │  │  ┌───────────────────────────────────────────────────────┐   │  │    │
│  │  │  │      RDS PostgreSQL (Worker Instance)                 │   │  │    │
│  │  │  │      supabase-worker-01 / db.t3.micro                 │   │  │    │
│  │  │  │                                                        │   │  │    │
│  │  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │   │  │    │
│  │  │  │  │ Tenant   │  │ Tenant   │  │ Tenant   │            │   │  │    │
│  │  │  │  │ DB-A     │  │ DB-B     │  │ DB-N     │            │   │  │    │
│  │  │  │  │ (supabase│  │ (supabase│  │ (supabase│            │   │  │    │
│  │  │  │  │  schema)  │  │  schema)  │  │  schema)  │            │   │  │    │
│  │  │  │  └──────────┘  └──────────┘  └──────────┘            │   │  │    │
│  │  │  └───────────────────────────────────────────────────────┘   │  │    │
│  │  │                                                               │  │    │
│  │  │  ┌───────────────────────────────────────────────────────┐   │  │    │
│  │  │  │      ElastiCache Redis (kong-cache)                   │   │  │    │
│  │  │  │      cache.t3.micro                                   │   │  │    │
│  │  │  │      - JWT secrets cache (TTL: 300s)                  │   │  │    │
│  │  │  │      - Lambda function URLs cache                     │   │  │    │
│  │  │  └───────────────────────────────────────────────────────┘   │  │    │
│  │  └───────────────────────────────────────────────────────────────┘  │    │
│  │                                                                       │    │
│  │  ┌────────────────────────────────────────────────────────────────┐  │    │
│  │  │              Supporting Services                               │  │    │
│  │  │                                                                │  │    │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │  │    │
│  │  │  │   Secrets    │  │   ECR        │  │   CloudWatch │        │  │    │
│  │  │  │   Manager    │  │   (Docker    │  │   Logs       │        │  │    │
│  │  │  │              │  │   Registry)  │  │              │        │  │    │
│  │  │  └──────────────┘  └──────────────┘  └──────────────┘        │  │    │
│  │  └────────────────────────────────────────────────────────────────┘  │    │
│  └───────────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────────┘

                    ┌──────────────────────────────────┐
                    │   Client Applications            │
                    │   - Supabase JS SDK              │
                    │   - Supabase Python SDK          │
                    │   - Direct REST API              │
                    │   - Studio Web UI                │
                    └──────────────────────────────────┘
```

### Architecture Highlights

1. **Multi-tenant isolation**: Each project has its own dedicated Lambda function and database
2. **API Gateway pattern**: Kong acts as the unified entry point, handling authentication, routing, and JWT minting
3. **Dynamic scaling**: Serverless architecture based on ECS Fargate and Lambda
4. **High availability**: Deployed across 2 Availability Zones, with automatic ALB failover
5. **Security isolation**: Internal VPC communication, with security groups strictly controlling access

---

## 2. Network and Infrastructure Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          VPC Network Architecture                            │
│                          CIDR: 10.0.0.0/16 (2 AZs)                          │
└─────────────────────────────────────────────────────────────────────────────┘

                              Internet Gateway
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
              ┌─────▼─────┐    ┌─────▼─────┐   ┌─────▼─────┐
              │  ALB SG   │    │  ALB SG   │   │  ALB SG   │
              │ (Kong)    │    │ (Studio)  │   │ (Tenant)  │
              │ 0.0.0.0   │    │ 0.0.0.0   │   │ 0.0.0.0   │
              │ :443      │    │ :443      │   │ :443      │
              └─────┬─────┘    └─────┬─────┘   └─────┬─────┘
                    │                │                │
┌───────────────────┼────────────────┼────────────────┼───────────────────────┐
│  Public Subnet    │                │                │                       │
│  (AZ-1)           │                │                │                       │
│  10.0.0.0/24      │                │                │                       │
└───────────────────┼────────────────┼────────────────┼───────────────────────┘
                    │                │                │
                    │         NAT Gateway (AZ-1)      │
                    │                │                │
┌───────────────────┼────────────────┼────────────────┼───────────────────────┐
│  Private Subnet   │                │                │                       │
│  (AZ-1)           │                │                │                       │
│  10.0.1.0/24      │                │                │                       │
│                   │                │                │                       │
│  ┌────────────────▼────────────────▼────────────────▼────────────────┐     │
│  │                    ECS Fargate Tasks                              │     │
│  │                                                                   │     │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │     │
│  │  │  Kong SG     │  │  Studio SG   │  │  Tenant SG   │           │     │
│  │  │  ALBSG:8000  │  │  ALBSG:8000  │  │  ALBSG:8080  │           │     │
│  │  │  TenantSG:   │  │              │  │  KongSG:8080 │           │     │
│  │  │    8001      │  │              │  │  LambdaSG:   │           │     │
│  │  │              │  │              │  │    8080      │           │     │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘           │     │
│  └─────────┼──────────────────┼──────────────────┼───────────────────┘     │
│            │                  │                  │                         │
│  ┌─────────▼──────────────────▼──────────────────▼───────────────────┐    │
│  │                    Lambda Functions (VPC)                          │    │
│  │                                                                    │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │  Lambda SG                                               │     │    │
│  │  │  - Outbound to RDS:5432                                  │     │    │
│  │  │  - Outbound to TenantMgr:8080                            │     │    │
│  │  └──────────────────────────────────────────────────────────┘     │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────┐     │
│  │                    Data Layer                                    │     │
│  │                                                                  │     │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    │     │
│  │  │  RDS SG        │  │  RDS SG        │  │  Redis SG      │    │     │
│  │  │  LambdaSG:5432 │  │  LambdaSG:5432 │  │  KongSG:6379   │    │     │
│  │  │  KongSG:5432   │  │  TenantSG:5432 │  │                │    │     │
│  │  │  TenantSG:5432 │  │                │  │                │    │     │
│  │  │                │  │                │  │                │    │     │
│  │  │  Primary RDS   │  │  Worker RDS    │  │  ElastiCache   │    │     │
│  │  │  (Platform)    │  │  (Tenants)     │  │  Redis         │    │     │
│  │  └────────────────┘  └────────────────┘  └────────────────┘    │     │
│  └──────────────────────────────────────────────────────────────────┘     │
└───────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────┐
│  Public Subnet (AZ-2) - 10.0.2.0/24                                       │
│  Private Subnet (AZ-2) - 10.0.3.0/24                                      │
│  (Similar layout for high availability)                                   │
└───────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────┐
│                      Security Group Rules Summary                          │
├───────────────────────────────────────────────────────────────────────────┤
│  ALBSG (sg-<ALBSG>)                                             │
│    Inbound: 0.0.0.0/0:443 (HTTPS from Internet)                           │
│    Outbound: KongSG:8000, StudioSG:8000, TenantSG:8080                    │
├───────────────────────────────────────────────────────────────────────────┤
│  KongSG (sg-<KongSG>)                                            │
│    Inbound: ALBSG:8000, TenantSG:8001                                     │
│    Outbound: RDS:5432, Redis:6379, TenantSG:8080, FunctionsSG:8080       │
├───────────────────────────────────────────────────────────────────────────┤
│  TenantManagerSG (sg-<TenantManagerSG>)                                   │
│    Inbound: KongSG:8080, LambdaSG:8080, ALBSG:8080                        │
│    Outbound: RDS:5432, Kong:8001                                          │
├───────────────────────────────────────────────────────────────────────────┤
│  LambdaSG (sg-<LambdaSG>)                                          │
│    Inbound: None                                                          │
│    Outbound: RDS:5432, TenantMgr:8080                                     │
├───────────────────────────────────────────────────────────────────────────┤
│  RdsSG (sg-<RdsSG>)                                             │
│    Inbound: LambdaSG:5432, KongSG:5432, TenantSG:5432                     │
│    Outbound: None                                                         │
├───────────────────────────────────────────────────────────────────────────┤
│  RedisSG (sg-<RedisSG>)                                           │
│    Inbound: KongSG:6379                                                   │
│    Outbound: None                                                         │
└───────────────────────────────────────────────────────────────────────────┘
```

### Network Design Highlights

1. **Multi-layer security**: Public subnet (ALB) → private subnet (application) → data layer (RDS/Redis)
2. **Least privilege**: Security groups strictly restrict ports and sources
3. **High availability**: Deployed across 2 AZs, single NAT Gateway (cost optimization)
4. **Service discovery**: AWS Cloud Map (kong.local namespace)
5. **SSL encryption**: SSL is enforced on all RDS connections


---

## 3. Request Flow Architecture (Gateway JWT Minting)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Client Request Flow (Gateway JWT Minting)                 │
│                    Pattern: Opaque API Key → Short-lived JWT                 │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  Client App      │
│  (Supabase SDK)  │
└────────┬─────────┘
         │
         │ 1. HTTP Request
         │    GET https://project-alpha.example.com/rest/v1/users
         │    Authorization: Bearer sb_publishable_abc123xyz...
         │    (The SDK automatically adds the API key as a Bearer token)
         │
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  ALB (Application Load Balancer)                                           │
│  - SSL Termination (ACM Certificate)                                       │
│  - Health Check: /health                                                   │
└────────┬───────────────────────────────────────────────────────────────────┘
         │
         │ 2. Forward to Kong
         │    Host: project-alpha.example.com
         │    Authorization: Bearer sb_publishable_abc123xyz...
         │
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  Kong Gateway (ECS Fargate)                                                │
│  DB-backed mode with PostgreSQL                                            │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │  Plugin Chain (executed in priority order)                           │ │
│  │                                                                        │ │
│  │  ┌────────────────────────────────────────────────────────────────┐  │ │
│  │  │  1. pre-function (Priority: 1000000)                           │  │ │
│  │  │     - Extract subdomain from the Host header                   │  │ │
│  │  │     - Host: project-alpha.example.com                       │  │ │
│  │  │     - Extract: "project-alpha"                                 │  │ │
│  │  │     - Set: X-Project-ID: project-alpha                         │  │ │
│  │  └────────────────────────────────────────────────────────────────┘  │ │
│  │                          │                                            │ │
│  │  ┌────────────────────────▼────────────────────────────────────────┐  │ │
│  │  │  2. key-auth (Priority: 1003)                                   │  │ │
│  │  │     - Extract API key from Authorization header                 │  │ │
│  │  │     - Query Kong DB: consumers table                            │  │ │
│  │  │     - Match consumer: "project-alpha--anon"                     │  │ │
│  │  │     - Remove Authorization header after successful auth         │  │ │
│  │  │       (hide_credentials: true)                                  │  │ │
│  │  │     - Set kong.client.authenticated_consumer                    │  │ │
│  │  └────────────────────────────────────────────────────────────────┘  │ │
│  │                          │                                            │ │
│  │  ┌────────────────────────▼────────────────────────────────────────┐  │ │
│  │  │  3. dynamic-lambda-router (Priority: 1001)                      │  │ │
│  │  │                                                                  │  │ │
│  │  │  Step 1: Resolve role                                           │  │ │
│  │  │    consumer = kong.client.get_consumer()                        │  │ │
│  │  │    username = "project-alpha--anon"                             │  │ │
│  │  │    role = "anon"  (parsed from username)                        │  │ │
│  │  │                                                                  │  │ │
│  │  │  Step 2: Fetch JWT Secret (Redis Cache)                         │  │ │
│  │  │    cache_key = "jwt:secret:project-alpha"                       │  │ │
│  │  │    jwt_secret = redis:get(cache_key)                            │  │ │
│  │  │    if not found:                                                │  │ │
│  │  │      GET http://tenant-manager:8080/project/project-alpha/config│  │ │
│  │  │      response: {project_id, function_url, jwt_secret}           │  │ │
│  │  │      redis:setex(cache_key, 300, jwt_secret)                    │  │ │
│  │  │                                                                  │  │ │
│  │  │  Step 3: Mint short-lived JWT (5-minute expiry)                 │  │ │
│  │  │    payload = {                                                  │  │ │
│  │  │      iss: "supabase",                                           │  │ │
│  │  │      ref: "project-alpha",                                      │  │ │
│  │  │      role: "anon",                                              │  │ │
│  │  │      iat: now(),                                                │  │ │
│  │  │      exp: now() + 300  // 5 minutes                             │  │ │
│  │  │    }                                                            │  │ │
│  │  │    jwt = HS256_sign(payload, jwt_secret)                        │  │ │
│  │  │                                                                  │  │ │
│  │  │  Step 4: Fetch Lambda Function URL (Redis Cache)                │  │ │
│  │  │    cache_key = "lambda:fn:project-alpha"                        │  │ │
│  │  │    function_url = redis:get(cache_key)                          │  │ │
│  │  │    if not found: (obtained from the Step 2 API response)        │  │ │
│  │  │      redis:setex(cache_key, 300, function_url)                  │  │ │
│  │  │                                                                  │  │ │
│  │  │  Step 5: SigV4-sign and invoke Lambda                           │  │ │
│  │  │    headers = {                                                  │  │ │
│  │  │      "X-Client-Authorization": "Bearer " .. jwt,               │  │ │
│  │  │      "Authorization": <SigV4 signature>                         │  │ │
│  │  │    }                                                            │  │ │
│  │  │    response = http.post(function_url, headers, body)            │  │ │
│  │  │                                                                  │  │ │
│  │  │  Step 6: Return response (short-circuit, no further plugins)    │  │ │
│  │  │    kong.response.exit(response.status, response.body)           │  │ │
│  │  └────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌────────────────────────────────────────────────────────────────┐  │ │
│  │  │  4. ACL (Priority: 950) - does not execute                     │  │ │
│  │  │     because dynamic-lambda-router already short-circuited      │  │ │
│  │  └────────────────────────────────────────────────────────────────┘  │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
└────────┬───────────────────────────────────────────────────────────────────┘
         │
         │ 3. Lambda Invocation (Function URL + SigV4)
         │    POST https://abc123.lambda-url.us-east-1.on.aws/
         │    X-Client-Authorization: Bearer eyJhbGc...  (short-lived JWT)
         │    Authorization: AWS4-HMAC-SHA256 ...  (SigV4)
         │
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  Lambda Function (PostgREST)                                               │
│  Function Name: postgrest-project-alpha                                    │
│  Memory: 512MB, VPC-enabled                                                │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │  Lambda Web Adapter (LWA)                                            │ │
│  │  - Intercepts the request                                            │ │
│  │  - X-Client-Authorization → Authorization                            │ │
│  │  - Forwards to PostgREST                                             │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                          │                                                │
│  ┌────────────────────────▼────────────────────────────────────────────┐  │
│  │  PostgREST Process                                                   │  │
│  │                                                                      │  │
│  │  1. Validate JWT                                                     │  │
│  │     - Extract JWT from Authorization header                          │  │
│  │     - Verify signature using jwt_secret                              │  │
│  │     - Check exp (expiration time)                                    │  │
│  │     - Extract role: "anon"                                           │  │
│  │                                                                      │  │
│  │  2. Set PostgreSQL session                                           │  │
│  │     SET LOCAL role TO 'anon';                                        │  │
│  │     SET LOCAL request.jwt.claims TO '{"role":"anon",...}';          │  │
│  │                                                                      │  │
│  │  3. Execute SQL query                                                │  │
│  │     SELECT * FROM users;                                             │  │
│  │     (subject to RLS policy)                                          │  │
│  │                                                                      │  │
│  │  4. Return JSON response                                             │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└────────┬───────────────────────────────────────────────────────────────────┘
         │
         │ 4. Database Query
         │    PostgreSQL connection with SSL
         │
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  RDS PostgreSQL (Worker Instance)                                          │
│  Database: supabase_project_alpha                                          │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │  Row Level Security (RLS) Enforcement                                │ │
│  │                                                                      │ │
│  │  CREATE POLICY "anon_select_policy" ON users                         │ │
│  │    FOR SELECT TO anon                                                │ │
│  │    USING (is_public = true);                                         │ │
│  │                                                                      │ │
│  │  Result: only rows with is_public = true are returned                │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
└────────┬───────────────────────────────────────────────────────────────────┘
         │
         │ 5. Response (JSON)
         │    [{"id": 1, "name": "Alice", "is_public": true}, ...]
         │
         ▼
┌──────────────────┐
│  Client App      │
│  (Receives data) │
└──────────────────┘
```

### Request Flow Key Points

1. **API Key format**:
   - Anon (publishable): `sb_publishable_{base64url_secret}`
   - Service Role (secret): `sb_secret_{base64url_secret}`

2. **Consumer naming convention**:
   - `{project_id}--anon` (double dash avoids ambiguity)
   - `{project_id}--service_role`

3. **JWT lifecycle**:
   - Dynamically minted by Kong, valid for 5 minutes
   - Limits the replay-attack window (vs. a 10-year static JWT)

4. **Caching strategy**:
   - Redis caches the JWT secret and Lambda URL
   - TTL: 300 seconds
   - Calls the tenant-manager API on a cache miss

5. **Security layers**:
   - Layer 1: ALB SSL termination
   - Layer 2: Kong key-auth verification
   - Layer 3: Lambda SigV4 signature
   - Layer 4: PostgREST JWT verification
   - Layer 5: PostgreSQL RLS policies


---

## 4. Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Data Flow Architecture                              │
│                   Platform Data vs Tenant Data Separation                    │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                        Platform Control Plane                                 │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  RDS PostgreSQL (Primary Instance)                                     │  │
│  │  Endpoint: supabase-rds.xxx.us-east-1.rds.amazonaws.com               │  │
│  │                                                                        │  │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │  │
│  │  │  Database: kong                                                   │ │  │
│  │  │  Purpose: Kong Gateway configuration storage                     │ │  │
│  │  │                                                                   │ │  │
│  │  │  Tables:                                                          │ │  │
│  │  │  ├─ consumers          (tenant consumer registration)            │ │  │
│  │  │  │   - id, username (project_id--role)                           │ │  │
│  │  │  │   - custom_id, created_at                                     │ │  │
│  │  │  │                                                               │ │  │
│  │  │  ├─ keyauth_credentials (API key credentials)                    │ │  │
│  │  │  │   - id, consumer_id                                           │ │  │
│  │  │  │   - key (sb_publishable_xxx / sb_secret_xxx)                  │ │  │
│  │  │  │   - created_at                                                │ │  │
│  │  │  │                                                               │ │  │
│  │  │  ├─ acls               (access control list)                     │ │  │
│  │  │  │   - id, consumer_id                                           │ │  │
│  │  │  │   - group (anon / admin)                                      │ │  │
│  │  │  │                                                               │ │  │
│  │  │  ├─ services           (backend service definitions)             │ │  │
│  │  │  ├─ routes             (routing rules)                           │ │  │
│  │  │  └─ plugins            (plugin configuration)                    │ │  │
│  │  └──────────────────────────────────────────────────────────────────┘ │  │
│  │                                                                        │  │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │  │
│  │  │  Database: supabase_platform                                      │ │  │
│  │  │  Purpose: Project metadata and configuration                     │ │  │
│  │  │                                                                   │ │  │
│  │  │  Tables:                                                          │ │  │
│  │  │  ├─ projects                                                      │ │  │
│  │  │  │   - id (project_id)                                           │ │  │
│  │  │  │   - function_name (Lambda function name)                      │ │  │
│  │  │  │   - function_url (Lambda Function URL)                        │ │  │
│  │  │  │   - function_arn                                              │ │  │
│  │  │  │   - status (active/inactive)                                  │ │  │
│  │  │  │   - created_at                                                │ │  │
│  │  │  │                                                               │ │  │
│  │  │  ├─ api_keys                                                      │ │  │
│  │  │  │   - id (UUID)                                                 │ │  │
│  │  │  │   - project_id (FK → projects.id)                            │ │  │
│  │  │  │   - name (anon / service_role)                                │ │  │
│  │  │  │   - key_type (publishable / secret)                           │ │  │
│  │  │  │   - role (anon / service_role)                                │ │  │
│  │  │  │   - key_value (the full opaque key)                           │ │  │
│  │  │  │   - hashed_secret (SHA256 hash)                               │ │  │
│  │  │  │   - created_at                                                │ │  │
│  │  │  │                                                               │ │  │
│  │  │  ├─ jwt_keys                                                      │ │  │
│  │  │  │   - id (UUID)                                                 │ │  │
│  │  │  │   - project_id (FK → projects.id)                            │ │  │
│  │  │  │   - secret (JWT signing secret)                               │ │  │
│  │  │  │   - algorithm (HS256)                                         │ │  │
│  │  │  │   - status (current / rotated)                                │ │  │
│  │  │  │   - created_at, rotated_at                                    │ │  │
│  │  │  │                                                               │ │  │
│  │  │  └─ postgrest_config                                              │ │  │
│  │  │      - project_id (PK, FK → projects.id)                         │ │  │
│  │  │      - db_uri (tenant database connection string)                │ │  │
│  │  │      - db_schemas (public)                                        │ │  │
│  │  │      - db_anon_role (anon)                                        │ │  │
│  │  │      - db_use_legacy_gucs (false)                                 │ │  │
│  │  └──────────────────────────────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  ElastiCache Redis (kong-cache)                                        │  │
│  │  Endpoint: kong-cache.xxx.cache.amazonaws.com:6379                     │  │
│  │                                                                        │  │
│  │  Cache Keys:                                                           │  │
│  │  ├─ jwt:secret:{project_id}  → JWT signing secret (TTL: 300s)         │  │
│  │  └─ lambda:fn:{project_id}   → Lambda Function URL (TTL: 300s)        │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  AWS Secrets Manager                                                    │  │
│  │  Purpose: Sensitive credential storage (Legacy, being migrated to RDS) │  │
│  │                                                                        │  │
│  │  Secrets:                                                              │  │
│  │  ├─ postgrest/{project_id}/config                                      │  │
│  │  │   {                                                                │  │
│  │  │     "project_id": "...",                                           │  │
│  │  │     "jwt_secret": "...",                                           │  │
│  │  │     "anon_key": "eyJhbGc...",  (JWT format, legacy)                │  │
│  │  │     "service_role_key": "eyJhbGc..."  (JWT format, legacy)         │  │
│  │  │   }                                                                │  │
│  │  │                                                                    │  │
│  │  └─ rds-credentials                                                    │  │
│  │      - Master password for RDS instances                              │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                         Tenant Data Plane                                     │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  RDS PostgreSQL (Worker Instance)                                      │  │
│  │  Instance ID: supabase-worker-01                                       │  │
│  │  Endpoint: supabase-worker-01.xxx.us-east-1.rds.amazonaws.com         │  │
│  │                                                                        │  │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │  │
│  │  │  Database: supabase_project_alpha                                 │ │  │
│  │  │  Owner: project_alpha_owner                                       │ │  │
│  │  │                                                                   │ │  │
│  │  │  Schemas:                                                         │ │  │
│  │  │  ├─ public (application data)                                    │ │  │
│  │  │  │   - users, posts, comments, ...                               │ │  │
│  │  │  │   - user-defined tables and data                              │ │  │
│  │  │  │                                                               │ │  │
│  │  │  ├─ auth (authentication data, future)                           │ │  │
│  │  │  │   - users, sessions, refresh_tokens                           │ │  │
│  │  │  │                                                               │ │  │
│  │  │  └─ storage (storage metadata, future)                           │ │  │
│  │  │      - buckets, objects                                          │ │  │
│  │  │                                                                   │ │  │
│  │  │  Roles:                                                           │ │  │
│  │  │  ├─ anon                                                          │ │  │
│  │  │  │   - GRANT SELECT, INSERT, UPDATE, DELETE ON public.*          │ │  │
│  │  │  │   - Subject to RLS policies                                   │ │  │
│  │  │  │                                                               │ │  │
│  │  │  ├─ service_role                                                  │ │  │
│  │  │  │   - GRANT ALL ON public.*                                     │ │  │
│  │  │  │   - BYPASSRLS (bypasses RLS policies)                         │ │  │
│  │  │  │                                                               │ │  │
│  │  │  └─ authenticated (future)                                       │ │  │
│  │  │      - Logged-in user role                                       │ │  │
│  │  │                                                                   │ │  │
│  │  │  RLS Policies:                                                    │ │  │
│  │  │  ├─ users_select_policy                                           │ │  │
│  │  │  │   FOR SELECT TO anon                                          │ │  │
│  │  │  │   USING (is_public = true)                                    │ │  │
│  │  │  │                                                               │ │  │
│  │  │  └─ users_insert_policy                                           │ │  │
│  │  │      FOR INSERT TO anon                                          │ │  │
│  │  │      WITH CHECK (user_id = auth.uid())                           │ │  │
│  │  └──────────────────────────────────────────────────────────────────┘ │  │
│  │                                                                        │  │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │  │
│  │  │  Database: supabase_project_beta                                  │ │  │
│  │  │  (similar structure, fully isolated)                             │ │  │
│  │  └──────────────────────────────────────────────────────────────────┘ │  │
│  │                                                                        │  │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │  │
│  │  │  Database: supabase_project_N                                     │ │  │
│  │  │  (one independent database per tenant)                           │ │  │
│  │  └──────────────────────────────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                      Data Access Patterns                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  1. Project Creation Flow:                                                   │
│     Studio → Tenant Manager → supabase_platform.projects (INSERT)            │
│                            → supabase_platform.api_keys (INSERT)              │
│                            → supabase_platform.jwt_keys (INSERT)              │
│                            → supabase_platform.postgrest_config (INSERT)      │
│                            → Kong Admin API (consumer + keyauth + ACL)        │
│                            → Lambda (CREATE function)                         │
│                            → Worker RDS (CREATE DATABASE)                     │
│                                                                               │
│  2. API Key Validation Flow:                                                 │
│     Client → Kong → kong.consumers (SELECT by key)                            │
│                  → kong.keyauth_credentials (JOIN)                            │
│                  → kong.acls (JOIN)                                           │
│                                                                               │
│  3. JWT Minting Flow:                                                        │
│     Kong Plugin → Redis (GET jwt:secret:{id})                                │
│                → Tenant Manager API (if cache miss)                          │
│                → supabase_platform.jwt_keys (SELECT)                          │
│                → Redis (SET jwt:secret:{id}, TTL 300)                         │
│                                                                               │
│  4. PostgREST Config Flow:                                                   │
│     Lambda Bootstrap → Tenant Manager API                                    │
│                     → supabase_platform.postgrest_config (SELECT)             │
│                     → Return {db_uri, db_schemas, db_anon_role}               │
│                                                                               │
│  5. Tenant Data Access Flow:                                                 │
│     Client → Kong → Lambda → Worker RDS.supabase_project_X                    │
│                                      → SET LOCAL role TO 'anon'               │
│                                      → SELECT * FROM users (RLS applied)      │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Data Architecture Key Points

1. **Data separation**:
   - **Platform DB**: Project metadata, configuration, API keys
   - **Kong DB**: Gateway configuration, consumers, routes
   - **Tenant DB**: Independent database per project, fully isolated

2. **Dual API Key storage**:
   - **Kong DB**: Full opaque key (`sb_publishable_xxx`) used for authentication
   - **Platform DB**: Opaque key + hashed secret used for management

3. **Caching strategy**:
   - Redis caches hot data (JWT secret, Lambda URL)
   - 5-minute TTL, balancing freshness and performance
   - Falls back to the tenant-manager API on cache miss

4. **Secure storage**:
   - SSL is enforced on RDS connections
   - Secrets Manager stores the RDS master password
   - API keys are stored using a SHA256 hash

5. **Scalability**:
   - Worker RDS can scale horizontally (add more instances)
   - Each instance can host multiple tenant databases
   - The load balancer selects the optimal instance


---

## 5. Service Component Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       Service Component Architecture                         │
│                       Microservices on ECS Fargate + Lambda                  │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                          API Gateway Layer                                    │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Kong Gateway (ECS Fargate)                                            │  │
│  │  Image: <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/kong-configured  │  │
│  │  Resources: 512 CPU / 1024 MB Memory                                   │  │
│  │  Desired Count: 1                                                      │  │
│  │                                                                        │  │
│  │  Responsibilities:                                                     │  │
│  │  ├─ API Gateway (unified entry point)                                  │  │
│  │  ├─ Subdomain routing (project-id extraction)                          │  │
│  │  ├─ API Key authentication (key-auth plugin)                           │  │
│  │  ├─ JWT minting (dynamic-lambda-router plugin)                         │  │
│  │  ├─ Lambda routing (SigV4 signing)                                     │  │
│  │  ├─ Access control (ACL plugin)                                        │  │
│  │  ├─ CORS handling                                                      │  │
│  │  └─ Request/response transformation                                    │  │
│  │                                                                        │  │
│  │  Configuration:                                                        │  │
│  │  ├─ Database: postgres (DB-backed mode)                                │  │
│  │  ├─ Admin API: :8001 (internal)                                        │  │
│  │  ├─ Proxy: :8000 (public via ALB)                                      │  │
│  │  ├─ Redis: kong-cache.xxx:6379                                         │  │
│  │  └─ Plugins: pre-function, key-auth, dynamic-lambda-router, ACL, CORS │  │
│  │                                                                        │  │
│  │  Custom Plugins:                                                       │  │
│  │  └─ dynamic-lambda-router/                                             │  │
│  │     ├─ handler.lua (core logic)                                        │  │
│  │     │   - mint_jwt()                                                  │  │
│  │     │   - get_project_config()                                        │  │
│  │     │   - sign_sigv4()                                                │  │
│  │     │   - invoke_lambda()                                             │  │
│  │     └─ schema.lua (config schema)                                      │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                        Management Layer                                       │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Tenant Manager (ECS Fargate)                                          │  │
│  │  Image: <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/tenant-manager   │  │
│  │  Resources: 512 CPU / 1024 MB Memory                                   │  │
│  │  Desired Count: 1                                                      │  │
│  │  Port: 8080 (Fastify)                                                  │  │
│  │                                                                        │  │
│  │  Responsibilities:                                                     │  │
│  │  ├─ Project lifecycle management (create, configure, delete)           │  │
│  │  ├─ API Key management (generate, list, revoke)                        │  │
│  │  ├─ Lambda function management (create, update, delete)                │  │
│  │  ├─ Kong Consumer registration                                         │  │
│  │  ├─ RDS instance management                                            │  │
│  │  ├─ Database initialization (schema + roles)                           │  │
│  │  └─ Config API (queried by Kong and Lambda)                            │  │
│  │                                                                        │  │
│  │  Modules:                                                              │  │
│  │  ├─ project/                                                           │  │
│  │  │   - project.service.ts (project CRUD)                               │  │
│  │  │   - project.controller.ts (REST API)                               │  │
│  │  │                                                                    │  │
│  │  ├─ api-keys/                                                          │  │
│  │  │   - api-key-generator.ts (opaque key generation)                    │  │
│  │  │   - api-key.service.ts (key CRUD)                                  │  │
│  │  │                                                                    │  │
│  │  ├─ provisioning/                                                      │  │
│  │  │   - provisioner.service.ts (Lambda + DB creation)                   │  │
│  │  │   - kong-consumer.service.ts (Kong Admin API)                      │  │
│  │  │                                                                    │  │
│  │  ├─ rds-instance/                                                      │  │
│  │  │   - rds-balancer.service.ts (instance selection)                    │  │
│  │  │   - rds-instance.repository.ts (instance metadata)                  │  │
│  │  │                                                                    │  │
│  │  └─ runtime-config/                                                    │  │
│  │      - config.controller.ts (config API)                               │  │
│  │                                                                        │  │
│  │  API Endpoints:                                                        │  │
│  │  ├─ POST   /project/create-pgrest-lambda                               │  │
│  │  ├─ GET    /project/:id/config                                         │  │
│  │  ├─ GET    /project/:id/postgrest-config                               │  │
│  │  ├─ GET    /project/:id/api-keys                                       │  │
│  │  ├─ POST   /project/:id/api-keys                                       │  │
│  │  └─ DELETE /project/:id/api-keys/:keyId                                │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Studio (ECS Fargate)                                                  │  │
│  │  Image: <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/studio           │  │
│  │  Resources: 512 CPU / 1024 MB Memory                                   │  │
│  │  Desired Count: 1                                                      │  │
│  │  Port: 8000 (Next.js)                                                  │  │
│  │                                                                        │  │
│  │  Responsibilities:                                                     │  │
│  │  ├─ Web UI (project management interface)                              │  │
│  │  ├─ SQL Editor (database queries)                                      │  │
│  │  ├─ Table Editor (visual table management)                             │  │
│  │  ├─ API Keys management                                                │  │
│  │  ├─ Database Metadata (tables, views, extensions)                      │  │
│  │  └─ Secrets management (future)                                        │  │
│  │                                                                        │  │
│  │  API Endpoints (Management API):                                       │  │
│  │  ├─ POST   /api/v1/projects                                            │  │
│  │  ├─ GET    /api/v1/projects                                            │  │
│  │  ├─ GET    /api/v1/projects/:ref                                       │  │
│  │  ├─ GET    /api/v1/projects/:ref/api-keys                              │  │
│  │  ├─ POST   /api/v1/projects/:ref/database/query                        │  │
│  │  ├─ GET    /api/v1/projects/:ref/database/tables                       │  │
│  │  ├─ GET    /api/v1/projects/:ref/database/views                        │  │
│  │  ├─ GET    /api/v1/projects/:ref/database/extensions                   │  │
│  │  └─ POST   /api/v1/projects/:ref/secrets (TODO)                        │  │
│  │                                                                        │  │
│  │  Integration:                                                          │  │
│  │  ├─ Backend: Tenant Manager (project management)                       │  │
│  │  ├─ Backend: postgres-meta (database metadata)                         │  │
│  │  └─ Frontend: React + Next.js                                          │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                         Compute Layer                                         │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  PostgREST Lambda (Per-Tenant)                                         │  │
│  │  Image: <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/postgrest-lambda │  │
│  │  Memory: 512 MB (configurable up to 2048 MB)                           │  │
│  │  Timeout: 30s                                                          │  │
│  │  VPC: Enabled (for RDS access)                                         │  │
│  │                                                                        │  │
│  │  Components:                                                           │  │
│  │  ├─ Lambda Web Adapter (LWA)                                           │  │
│  │  │   - HTTP → Lambda event conversion                                  │  │
│  │  │   - X-Client-Authorization → Authorization                         │  │
│  │  │                                                                    │  │
│  │  ├─ PostgREST Binary                                                   │  │
│  │  │   - RESTful API for PostgreSQL                                     │  │
│  │  │   - JWT verification                                                │  │
│  │  │   - RLS enforcement                                                 │  │
│  │  │                                                                    │  │
│  │  └─ bootstrap.sh                                                       │  │
│  │      - Fetches configuration at startup                                │  │
│  │      - from the tenant-manager API or Secrets Manager                  │  │
│  │                                                                        │  │
│  │  Environment Variables:                                                │  │
│  │  ├─ PROJECT_ID (project identifier)                                    │  │
│  │  ├─ CONFIG_SOURCE (service / secretsmanager)                           │  │
│  │  ├─ CONFIG_SERVICE_URL (tenant-manager endpoint)                       │  │
│  │  └─ AWS_LWA_PORT (8080)                                                │  │
│  │                                                                        │  │
│  │  Configuration (from tenant-manager):                                  │  │
│  │  ├─ PGRST_DB_URI (database connection string)                          │  │
│  │  ├─ PGRST_DB_SCHEMAS (public)                                          │  │
│  │  ├─ PGRST_DB_ANON_ROLE (anon)                                          │  │
│  │  ├─ PGRST_JWT_SECRET (JWT verification secret)                         │  │
│  │  └─ PGRST_DB_USE_LEGACY_GUCS (false)                                   │  │
│  │                                                                        │  │
│  │  Invocation:                                                           │  │
│  │  ├─ Function URL (public, IAM auth)                                    │  │
│  │  ├─ SigV4 signing (by Kong)                                            │  │
│  │  └─ Cold start: ~1-2s, Warm: <100ms                                    │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Functions Service (ECS Fargate)                                       │  │
│  │  Image: <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/functions-service│  │
│  │  Resources: 256 CPU / 512 MB Memory                                    │  │
│  │  Desired Count: 1                                                      │  │
│  │  Port: 8080                                                            │  │
│  │                                                                        │  │
│  │  Responsibilities:                                                     │  │
│  │  ├─ Edge Functions execution (Deno runtime)                            │  │
│  │  ├─ Function deployment and version management                         │  │
│  │  ├─ Environment variable injection                                     │  │
│  │  └─ Log collection                                                     │  │
│  │                                                                        │  │
│  │  API Endpoints:                                                        │  │
│  │  ├─ POST   /functions/v1/:function_name                                │  │
│  │  ├─ GET    /functions/v1/:function_name                                │  │
│  │  └─ DELETE /functions/v1/:function_name                                │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                        Supporting Services                                    │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  postgres-meta (ECS Fargate)                                           │  │
│  │  Image: <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/postgres-meta    │  │
│  │  Resources: 256 CPU / 512 MB Memory                                    │  │
│  │  Port: 8080                                                            │  │
│  │                                                                        │  │
│  │  Responsibilities:                                                     │  │
│  │  ├─ PostgreSQL metadata API                                            │  │
│  │  ├─ Table, view, column, and index queries                             │  │
│  │  ├─ Extension, function, and trigger management                        │  │
│  │  └─ Schema visualization                                               │  │
│  │                                                                        │  │
│  │  Used by: Studio (database metadata endpoints)                         │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  db-admin Lambda                                                       │  │
│  │  Image: <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/db-admin-lambda  │  │
│  │  Memory: 256 MB                                                        │  │
│  │                                                                        │  │
│  │  Responsibilities:                                                     │  │
│  │  ├─ Database management operations (list_databases, execute_sql)       │  │
│  │  ├─ Testing and debugging tools                                        │  │
│  │  └─ Direct SQL execution                                               │  │
│  │                                                                        │  │
│  │  Operations:                                                           │  │
│  │  ├─ list_databases                                                     │  │
│  │  └─ execute_sql (database, sql)                                        │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                      Service Communication                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  Service Discovery (AWS Cloud Map):                                          │
│  ├─ Namespace: kong.local (private DNS)                                      │
│  ├─ kong-gateway.kong.local:8000 (proxy)                                     │
│  ├─ kong-gateway.kong.local:8001 (admin)                                     │
│  ├─ tenant-manager.kong.local:8080                                            │
│  ├─ functions-service.kong.local:8080                                         │
│  └─ postgres-meta.kong.local:8080                                             │
│                                                                               │
│  Communication Patterns:                                                      │
│  ├─ Client → ALB → Kong (HTTPS)                                              │
│  ├─ Kong → Lambda (Function URL + SigV4)                                      │
│  ├─ Kong → Tenant Manager (HTTP, internal)                                   │
│  ├─ Kong → Functions Service (HTTP, internal)                                │
│  ├─ Tenant Manager → Kong Admin API (HTTP, :8001)                            │
│  ├─ Tenant Manager → RDS (PostgreSQL, SSL)                                   │
│  ├─ Lambda → Tenant Manager (HTTP, internal)                                 │
│  ├─ Lambda → RDS (PostgreSQL, SSL)                                           │
│  ├─ Studio → Tenant Manager (HTTP, internal)                                 │
│  └─ Studio → postgres-meta (HTTP, internal)                                  │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Service Component Key Points

1. **Kong Gateway**:
   - Unified API entry point, handling all external requests
   - DB-backed mode with dynamic consumer registration
   - Custom plugins implement JWT minting and Lambda routing

2. **Tenant Manager**:
   - Core management service, consolidating the former project-service functionality
   - Responsible for the complete project lifecycle
   - Provides the config API queried by Kong and Lambda

3. **PostgREST Lambda**:
   - Independent Lambda function per tenant
   - Cold-start optimization: 512MB memory, VPC pre-warming
   - Lambda Web Adapter implements the HTTP → Lambda conversion

4. **Studio**:
   - Management UI based on the official Supabase Studio
   - Integrates with tenant-manager and postgres-meta
   - Provides a unified project management experience

5. **Service discovery**:
   - AWS Cloud Map provides internal DNS
   - Services communicate with each other via DNS names
   - No hardcoded IP addresses required


---

## 6. Security Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Security Architecture                               │
│                     Defense in Depth - Multi-Layer Security Protection       │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                        Layer 1: Network Security                              │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  VPC Isolation                                                         │  │
│  │  ├─ Private Subnets (application layer)                                │  │
│  │  │   - No direct Internet access                                       │  │
│  │  │   - Outbound traffic via NAT Gateway                                │  │
│  │  │                                                                    │  │
│  │  ├─ Security Groups (Stateful Firewall)                                │  │
│  │  │   - Least-privilege principle                                       │  │
│  │  │   - Only allows necessary ports and sources                         │  │
│  │  │   - Denies all traffic not explicitly allowed                       │  │
│  │  │                                                                    │  │
│  │  └─ Network ACLs (Stateless Firewall)                                  │  │
│  │      - Subnet-level access control                                     │  │
│  │      - An additional layer of protection                               │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Security Group Rules (detailed)                                       │  │
│  │                                                                        │  │
│  │  ALBSG → KongSG                                                        │  │
│  │    ✓ TCP 8000 (Kong Proxy)                                             │  │
│  │    ✗ All other ports                                                   │  │
│  │                                                                        │  │
│  │  KongSG → RdsSG                                                        │  │
│  │    ✓ TCP 5432 (PostgreSQL)                                             │  │
│  │    ✗ All other ports                                                   │  │
│  │                                                                        │  │
│  │  KongSG → RedisSG                                                      │  │
│  │    ✓ TCP 6379 (Redis)                                                  │  │
│  │    ✗ All other ports                                                   │  │
│  │                                                                        │  │
│  │  LambdaSG → RdsSG                                                      │  │
│  │    ✓ TCP 5432 (PostgreSQL)                                             │  │
│  │    ✗ All other ports                                                   │  │
│  │                                                                        │  │
│  │  TenantManagerSG → RdsSG                                                │  │
│  │    ✓ TCP 5432 (PostgreSQL)                                             │  │
│  │    ✗ All other ports                                                   │  │
│  │                                                                        │  │
│  │  RdsSG                                                                  │  │
│  │    ✓ Inbound from LambdaSG, KongSG, TenantManagerSG only               │  │
│  │    ✗ No outbound (data layer isolation)                                │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────────┐
│                      Layer 2: Transport Security                                  │
│                                                                                   │
│  ┌────────────────────────────────────────────────────────────────────────────┐  │
│  │  TLS/SSL Encryption                                                        │  │
│  │                                                                            │  │
│  │  Client → ALB                                                              │  │
│  │    ✓ HTTPS (TLS 1.2+)                                                      │  │
│  │    ✓ ACM Certificate (*.example.com)                                    │  │
│  │    ✓ Strong cipher suites                                                  │  │
│  │                                                                            │  │
│  │  ALB → Kong                                                                │  │
│  │    ○ HTTP (internal VPC, encrypted at network layer)                       │  │
│  │                                                                            │  │
│  │  Kong → Lambda                                                             │  │
│  │    ✓ HTTPS (Function URL with TLS)                                         │  │
│  │    ✓ SigV4 signature                                                       │  │
│  │                                                                            │  │
│  │  Lambda/Kong/TenantManager → RDS                                           │  │
│  │    ✓ PostgreSQL SSL (required)                                             │  │
│  │    ✓ ssl=on, sslmode=require                                               │  │
│  │    ○ sslverify=off (RDS managed cert)                                      │  │
│  │                                                                            │  │
│  │  Kong → Redis                                                              │  │
│  │    ○ Unencrypted (internal VPC; encryption in transit optional)            │  │
│  └────────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                    Layer 3: Authentication & Authorization                    │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  API Key Authentication (Kong key-auth)                                │  │
│  │                                                                        │  │
│  │  1. Client sends the request                                           │  │
│  │     Authorization: Bearer sb_publishable_abc123xyz...                  │  │
│  │                                                                        │  │
│  │  2. Kong extracts the API key                                          │  │
│  │     key = extract_from_header("Authorization")                         │  │
│  │                                                                        │  │
│  │  3. Kong DB query                                                      │  │
│  │     SELECT c.* FROM consumers c                                        │  │
│  │     JOIN keyauth_credentials k ON k.consumer_id = c.id                 │  │
│  │     WHERE k.key = 'sb_publishable_abc123xyz...'                        │  │
│  │                                                                        │  │
│  │  4. Verification succeeds                                              │  │
│  │     - Sets authenticated_consumer                                      │  │
│  │     - Removes the Authorization header (hide_credentials: true)        │  │
│  │     - Continues executing subsequent plugins                           │  │
│  │                                                                        │  │
│  │  5. Verification fails                                                 │  │
│  │     - Returns 401 Unauthorized                                         │  │
│  │     - Logs the failure                                                 │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  JWT Authentication (PostgREST)                                        │  │
│  │                                                                        │  │
│  │  1. Kong mints a short-lived JWT                                       │  │
│  │     payload = {                                                        │  │
│  │       iss: "supabase",                                                 │  │
│  │       ref: "project-alpha",                                            │  │
│  │       role: "anon",                                                    │  │
│  │       iat: 1709123456,                                                 │  │
│  │       exp: 1709123756  // 5 minutes                                    │  │
│  │     }                                                                  │  │
│  │     jwt = HS256_sign(payload, jwt_secret)                              │  │
│  │                                                                        │  │
│  │  2. Lambda receives the JWT                                            │  │
│  │     Authorization: Bearer <jwt-token>...                                │  │
│  │                                                                        │  │
│  │  3. PostgREST verifies the JWT                                         │  │
│  │     - Verifies the signature (using jwt_secret)                        │  │
│  │     - Checks exp (expiration time)                                     │  │
│  │     - Checks iss (issuer)                                              │  │
│  │     - Extracts role                                                    │  │
│  │                                                                        │  │
│  │  4. Sets the PostgreSQL session                                        │  │
│  │     SET LOCAL role TO 'anon';                                          │  │
│  │     SET LOCAL request.jwt.claims TO '{"role":"anon",...}';            │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Access Control (Kong ACL + PostgreSQL RLS)                            │  │
│  │                                                                        │  │
│  │  Kong ACL:                                                             │  │
│  │  ├─ Consumer: project-alpha--anon                                      │  │
│  │  │   ACL Group: anon                                                   │  │
│  │  │   Allowed Routes: /rest/v1/* (read-only operations)                │  │
│  │  │                                                                    │  │
│  │  └─ Consumer: project-alpha--service_role                              │  │
│  │      ACL Group: admin                                                  │  │
│  │      Allowed Routes: /rest/v1/* (all operations)                       │  │
│  │                                                                        │  │
│  │  PostgreSQL RLS:                                                       │  │
│  │  ├─ Role: anon                                                         │  │
│  │  │   - Subject to RLS policies                                        │  │
│  │  │   - GRANT SELECT, INSERT, UPDATE, DELETE ON public.*               │  │
│  │  │   - Policies enforce row-level access                              │  │
│  │  │                                                                    │  │
│  │  └─ Role: service_role                                                 │  │
│  │      - BYPASSRLS (bypasses RLS)                                        │  │
│  │      - GRANT ALL ON public.*                                           │  │
│  │      - Full database access privileges                                 │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────────┐
│                      Layer 4: Data Security                                     │
│                                                                                 │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  Encryption at Rest                                                    │    │
│  │                                                                        │    │
│  │  RDS PostgreSQL:                                                       │    │
│  │  ✓ Storage encryption enabled (AWS KMS)                                │    │
│  │  ✓ Automated backups encrypted                                         │    │
│  │  ✓ Snapshots encrypted                                                 │    │
│  │                                                                        │    │
│  │  Secrets Manager:                                                      │    │
│  │  ✓ Secrets encrypted with KMS                                          │    │
│  │  ✓ Automatic rotation support                                          │    │
│  │                                                                        │    │
│  │  ElastiCache Redis:                                                    │    │
│  │  ○ At-rest encryption (optional, not enabled)                          │    │
│  │  ○ In-transit encryption (optional, not enabled)                       │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │
│  │  Sensitive Data Handling                                                 │  │
│  │                                                                          │  │
│  │  API Keys:                                                               │  │
│  │  ├─ Storage: supabase_platform.api_keys                                  │  │
│  │  │   - key_value: the full opaque key (used for Kong authentication)     │  │
│  │  │   - hashed_secret: SHA256(secret) (used for verification)             │  │
│  │  │                                                                       │  │
│  │  ├─ Transmission: HTTPS only                                             │  │
│  │  └─ Display: full key shown only at creation; prefix only thereafter     │  │
│  │  │                                                                       │  │
│  │  JWT Secrets:                                                            │  │
│  │  ├─ Storage: supabase_platform.jwt_keys                                  │  │
│  │  │   - secret: 256-bit random string                                    │  │
│  │  │   - algorithm: HS256                                                  │  │
│  │  │                                                                       │  │
│  │  ├─ Caching: Redis (TTL 300s)                                            │  │
│  │  └─ Transmission: Internal VPC only                                      │  │
│  │  │                                                                       │  │
│  │  Database Credentials:                                                   │  │
│  │  ├─ Master password: Secrets Manager (auto-generated)                    │  │
│  │  ├─ Tenant passwords: Generated per-project                              │  │
│  │  └─ Connection strings: Environment variables (encrypted)                │  │
│  └──────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  Multi-Tenant Isolation                                                │    │
│  │                                                                        │    │
│  │  Database Level:                                                       │    │
│  │  ├─ Independent database per tenant                                    │    │
│  │  ├─ Independent database owner role                                    │    │
│  │  ├─ No cross-database query capability                                 │    │
│  │  └─ Physical isolation (separate RDS instances optional)               │    │
│  │                                                                        │    │
│  │  Lambda Level:                                                         │    │
│  │  ├─ Independent Lambda function per tenant                             │    │
│  │  ├─ Independent execution environment                                  │    │
│  │  ├─ Independent IAM role                                               │    │
│  │  └─ Independent log stream                                             │    │
│  │                                                                        │    │
│  │  Network Level:                                                        │    │
│  │  ├─ Kong routing isolation (based on project_id)                       │    │
│  │  ├─ Security Group isolation                                           │    │
│  │  └─ Internal VPC communication                                         │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                      Layer 5: Operational Security                            │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  IAM Roles & Policies                                                  │  │
│  │                                                                        │  │
│  │  ECS Task Role (Kong, Tenant Manager, Studio):                         │  │
│  │  ├─ ecr:GetAuthorizationToken                                          │  │
│  │  ├─ ecr:BatchGetImage                                                  │  │
│  │  ├─ logs:CreateLogStream, logs:PutLogEvents                            │  │
│  │  ├─ secretsmanager:GetSecretValue (RDS credentials)                    │  │
│  │  └─ servicediscovery:DiscoverInstances                                 │  │
│  │                                                                        │  │
│  │  Lambda Execution Role (PostgREST):                                    │  │
│  │  ├─ logs:CreateLogGroup, logs:CreateLogStream, logs:PutLogEvents      │  │
│  │  ├─ ec2:CreateNetworkInterface, ec2:DescribeNetworkInterfaces (VPC)   │  │
│  │  ├─ secretsmanager:GetSecretValue (config, optional)                   │  │
│  │  └─ rds:DescribeDBInstances (optional)                                 │  │
│  │                                                                        │  │
│  │  Tenant Manager Role (additional permissions):                         │  │
│  │  ├─ lambda:CreateFunction, lambda:UpdateFunctionCode                   │  │
│  │  ├─ lambda:CreateFunctionUrlConfig                                     │  │
│  │  ├─ iam:PassRole (Lambda execution role)                               │  │
│  │  ├─ secretsmanager:CreateSecret, secretsmanager:PutSecretValue         │  │
│  │  └─ rds:CreateDBInstance (optional, for dedicated instances)           │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Logging & Monitoring                                                  │  │
│  │                                                                        │  │
│  │  CloudWatch Logs:                                                      │  │
│  │  ├─ /ecs/supabase (Kong, Tenant Manager, Studio, Functions)            │  │
│  │  ├─ /aws/lambda/postgrest-{project_id} (per-tenant)                    │  │
│  │  └─ /aws/rds/instance/{instance_id}/postgresql (RDS logs)              │  │
│  │                                                                        │  │
│  │  Audit Logging:                                                        │  │
│  │  ├─ Kong access logs (all API requests)                                │  │
│  │  ├─ Tenant Manager operation logs (project CRUD)                       │  │
│  │  ├─ Lambda invocation logs (PostgREST queries)                         │  │
│  │  └─ RDS query logs (slow queries, errors)                              │  │
│  │                                                                        │  │
│  │  Security Monitoring:                                                  │  │
│  │  ├─ Failed authentication attempts (Kong 401 responses)                │  │
│  │  ├─ Unusual API usage patterns                                         │  │
│  │  ├─ Lambda cold start metrics                                          │  │
│  │  └─ RDS connection pool exhaustion                                     │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Secrets Rotation                                                      │  │
│  │                                                                        │  │
│  │  RDS Master Password:                                                  │  │
│  │  ├─ Stored in Secrets Manager                                          │  │
│  │  ├─ Automatic rotation (configurable)                                  │  │
│  │  └─ Zero-downtime rotation                                             │  │
│  │                                                                        │  │
│  │  API Keys:                                                             │  │
│  │  ├─ Manual rotation (via Studio/API)                                   │  │
│  │  ├─ Create new key → update application → delete old key               │  │
│  │  └─ Supports multiple active keys (transition period)                  │  │
│  │                                                                        │  │
│  │  JWT Secrets:                                                          │  │
│  │  ├─ Manual rotation (requires coordination)                            │  │
│  │  ├─ Update supabase_platform.jwt_keys                                  │  │
│  │  ├─ Clear the Redis cache                                              │  │
│  │  └─ Restart Lambda (automatically picks up the new secret)             │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────────┐
│                      Security Best Practices                                    │
├────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ✓ Principle of Least Privilege (least-privilege principle)                    │
│    - IAM roles are granted only the necessary permissions                      │
│    - Security groups open only the necessary ports                             │
│    - Database roles are granted only the necessary table permissions           │
│                                                                                 │
│  ✓ Defense in Depth                                                            │
│    - 5 layers of security: network, transport, auth, data, operations          │
│    - A single point of failure does not compromise overall security            │
│                                                                                 │
│  ✓ Encryption Everywhere                                                       │
│    - Encryption in transit: HTTPS, PostgreSQL SSL                              │
│    - Encryption at rest: RDS storage, Secrets Manager                          │
│                                                                                 │
│  ✓ Multi-Tenant Isolation                                                      │
│    - Database-level isolation                                                  │
│    - Lambda function isolation                                                 │
│    - Network routing isolation                                                 │
│                                                                                 │
│  ✓ Short-Lived Credentials                                                     │
│    - JWT has a 5-minute expiry                                                 │
│    - Limits the replay-attack window                                           │
│                                                                                 │
│  ✓ Audit & Monitoring                                                          │
│    - All API requests are logged                                               │
│    - Alerts on failed authentication                                           │
│    - Anomalous behavior detection                                              │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Security Architecture Key Points

1. **Multi-layer protection**: 5 layers of security ensure a single point of failure does not cause total system failure
2. **Least privilege**: All components are granted only the minimum permissions necessary
3. **Encrypted transport**: All sensitive data transmission uses TLS/SSL encryption
4. **Tenant isolation**: Three-layer isolation across database, Lambda, and network
5. **Short-lived credentials**: JWT's 5-minute expiry limits replay attacks
6. **Audit logging**: Complete operation logs used for security auditing


---

## 7. Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Deployment Architecture                              │
│                    CI/CD Pipeline & Infrastructure as Code                   │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                        Infrastructure as Code (AWS CDK)                       │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  CDK Stack Structure                                                   │  │
│  │                                                                        │  │
│  │  infra/                                                                │  │
│  │  ├─ bin/                                                               │  │
│  │  │   └─ kong-ecs-fargate.ts (CDK app entry point)                     │  │
│  │  │                                                                    │  │
│  │  ├─ lib/                                                               │  │
│  │  │   └─ supabase-stack.ts (Main stack definition)                     │  │
│  │  │       ├─ VPC (2 AZs, 1 NAT Gateway)                                │  │
│  │  │       ├─ Security Groups (7 groups)                                │  │
│  │  │       ├─ RDS PostgreSQL (Primary + Worker)                         │  │
│  │  │       ├─ ElastiCache Redis                                         │  │
│  │  │       ├─ ECS Cluster                                               │  │
│  │  │       ├─ ECS Services (Kong, Tenant Manager, Studio, Functions)    │  │
│  │  │       ├─ Application Load Balancers (3)                            │  │
│  │  │       ├─ AWS Cloud Map (Service Discovery)                         │  │
│  │  │       └─ IAM Roles & Policies                                      │  │
│  │  │                                                                    │  │
│  │  ├─ cdk.json (CDK configuration)                                       │  │
│  │  ├─ package.json (Dependencies)                                        │  │
│  │  └─ tsconfig.json (TypeScript config)                                  │  │
│  │                                                                        │  │
│  │  Configuration Source:                                                 │  │
│  │  └─ config.json (Project root)                                         │  │
│  │      - Single source of truth                                          │  │
│  │      - ECR URIs, resource allocations, domain config                   │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  CDK Deployment Commands                                               │  │
│  │                                                                        │  │
│  │  # Bootstrap CDK (first time only)                                     │  │
│  │  cdk bootstrap aws://<AWS_ACCOUNT_ID>/us-east-1                            │  │
│  │                                                                        │  │
│  │  # Synthesize CloudFormation template                                  │  │
│  │  cd infra && npm run build && cdk synth                                │  │
│  │                                                                        │  │
│  │  # Deploy stack                                                        │  │
│  │  cdk deploy SupabaseStack                                              │  │
│  │                                                                        │  │
│  │  # Diff changes                                                        │  │
│  │  cdk diff SupabaseStack                                                │  │
│  │                                                                        │  │
│  │  # Destroy stack (careful!)                                            │  │
│  │  cdk destroy SupabaseStack                                             │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                        Container Build & Push Pipeline                        │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Build Script (build-and-push.sh)                                      │  │
│  │                                                                        │  │
│  │  Usage:                                                                │  │
│  │  ./build-and-push.sh [service]                                         │  │
│  │                                                                        │  │
│  │  Services:                                                             │  │
│  │  ├─ kong           (Kong Gateway with custom plugins)                  │  │
│  │  ├─ tenant-manager (Tenant management service)                         │  │
│  │  ├─ project        (Legacy project service)                            │  │
│  │  ├─ postgrest-lambda (PostgREST Lambda container)                      │  │
│  │  ├─ functions      (Edge Functions service)                            │  │
│  │  ├─ studio         (Supabase Studio)                                   │  │
│  │  └─ all            (Build all services)                                │  │
│  │                                                                        │  │
│  │  Build Process:                                                        │  │
│  │  1. Read config.json for ECR URIs                                      │  │
│  │  2. AWS ECR login                                                      │  │
│  │  3. Docker build (multi-stage for optimization)                        │  │
│  │  4. Docker tag (latest + git commit hash)                              │  │
│  │  5. Docker push to ECR                                                 │  │
│  │  6. Output image URI                                                   │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  ECR Repositories                                                      │  │
│  │                                                                        │  │
│  │  <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/                         │  │
│  │  ├─ kong-configured                                                    │  │
│  │  │   Base: kong:3.5                                                    │  │
│  │  │   + Custom plugins (dynamic-lambda-router)                          │  │
│  │  │   + kong.yml.tpl                                                    │  │
│  │  │   + docker-entrypoint-custom.sh                                     │  │
│  │  │                                                                    │  │
│  │  ├─ tenant-manager                                                     │  │
│  │  │   Base: node:20-alpine                                              │  │
│  │  │   + TypeScript compiled code                                        │  │
│  │  │   + Dependencies (Fastify, Kysely, pg)                              │  │
│  │  │                                                                    │  │
│  │  ├─ postgrest-lambda                                                   │  │
│  │  │   Base: public.ecr.aws/lambda/provided:al2                          │  │
│  │  │   + PostgREST binary                                                │  │
│  │  │   + Lambda Web Adapter                                              │  │
│  │  │   + bootstrap.sh                                                    │  │
│  │  │                                                                    │  │
│  │  ├─ studio                                                             │  │
│  │  │   Base: node:20-alpine                                              │  │
│  │  │   + Next.js build                                                   │  │
│  │  │   + Supabase Studio frontend                                        │  │
│  │  │                                                                    │  │
│  │  ├─ functions-service                                                  │  │
│  │  │   Base: denoland/deno:alpine                                        │  │
│  │  │   + Edge Functions runtime                                          │  │
│  │  │                                                                    │  │
│  │  └─ db-admin-lambda                                                    │  │
│  │      Base: public.ecr.aws/lambda/python:3.12                           │  │
│  │      + psycopg2 + boto3                                                │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                        ECS Service Deployment                                 │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Deployment Process                                                    │  │
│  │                                                                        │  │
│  │  1. Build & Push Image                                                 │  │
│  │     ./build-and-push.sh kong                                           │  │
│  │     → Image: kong-configured:abc123                                    │  │
│  │                                                                        │  │
│  │  2. Update ECS Task Definition (automatic)                             │  │
│  │     - ECS pulls latest image from ECR                                  │  │
│  │     - Creates new task definition revision                             │  │
│  │                                                                        │  │
│  │  3. Force New Deployment                                               │  │
│  │     aws ecs update-service \                                           │  │
│  │       --cluster <ECS_CLUSTER> \                                   │  │
│  │       --service kong-gateway \                                         │  │
│  │       --force-new-deployment \                                         │  │
│  │       --region us-east-1                                               │  │
│  │                                                                        │  │
│  │  4. Rolling Update                                                     │  │
│  │     - ECS starts new task with new image                               │  │
│  │     - Health check passes                                              │  │
│  │     - ALB routes traffic to new task                                   │  │
│  │     - Old task drains connections                                      │  │
│  │     - Old task terminates                                              │  │
│  │                                                                        │  │
│  │  5. Verify Deployment                                                  │  │
│  │     aws ecs describe-services \                                        │  │
│  │       --cluster <ECS_CLUSTER> \                                   │  │
│  │       --services kong-gateway \                                        │  │
│  │       --query 'services[0].[serviceName,status,runningCount]'         │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Rollback Strategy                                                     │  │
│  │                                                                        │  │
│  │  Option 1: Revert to Previous Task Definition                          │  │
│  │  aws ecs update-service \                                              │  │
│  │    --cluster <ECS_CLUSTER> \                                      │  │
│  │    --service kong-gateway \                                            │  │
│  │    --task-definition kong-gateway:42  # previous revision              │  │
│  │                                                                        │  │
│  │  Option 2: Rebuild & Deploy Previous Image                             │  │
│  │  git checkout <previous-commit>                                        │  │
│  │  ./build-and-push.sh kong                                              │  │
│  │  aws ecs update-service --force-new-deployment ...                     │  │
│  │                                                                        │  │
│  │  Option 3: CDK Rollback (infrastructure changes)                       │  │
│  │  cdk deploy SupabaseStack --rollback                                   │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                        Lambda Deployment                                      │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Per-Tenant Lambda Creation (via Tenant Manager)                       │  │
│  │                                                                        │  │
│  │  POST /project/create-pgrest-lambda                                    │  │
│  │  {                                                                     │  │
│  │    "projectId": "project-alpha"                                        │  │
│  │  }                                                                     │  │
│  │                                                                        │  │
│  │  Process:                                                              │  │
│  │  1. Generate project metadata (API keys, JWT secret)                   │  │
│  │  2. Create tenant database on Worker RDS                               │  │
│  │  3. Initialize database (schema, roles, RLS)                           │  │
│  │  4. Create Lambda function                                             │  │
│  │     - Function name: postgrest-project-alpha                           │  │
│  │     - Image: postgrest-lambda:latest                                   │  │
│  │     - Memory: 512 MB                                                   │  │
│  │     - Timeout: 30s                                                     │  │
│  │     - VPC: Enabled                                                     │  │
│  │     - Environment:                                                     │  │
│  │       PROJECT_ID=project-alpha                                         │  │
│  │       CONFIG_SOURCE=service                                            │  │
│  │       CONFIG_SERVICE_URL=http://tenant-manager:8080                    │  │
│  │  5. Create Function URL (public, IAM auth)                             │  │
│  │  6. Register Kong consumers (anon + service_role)                      │  │
│  │  7. Store metadata in supabase_platform DB                             │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Lambda Image Update (Global)                                          │  │
│  │                                                                        │  │
│  │  1. Build & Push New Image                                             │  │
│  │     ./build-and-push.sh postgrest-lambda                               │  │
│  │     → Image: postgrest-lambda:def456                                   │  │
│  │                                                                        │  │
│  │  2. Update All Tenant Lambdas (Script)                                 │  │
│  │     for project in $(list_all_projects); do                            │  │
│  │       aws lambda update-function-code \                                │  │
│  │         --function-name postgrest-$project \                           │  │
│  │         --image-uri <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/\     │  │
│  │                     postgrest-lambda:def456                            │  │
│  │     done                                                               │  │
│  │                                                                        │  │
│  │  3. Wait for Updates to Complete                                       │  │
│  │     aws lambda wait function-updated \                                 │  │
│  │       --function-name postgrest-$project                               │  │
│  │                                                                        │  │
│  │  4. Verify (Test Request)                                              │  │
│  │     curl https://project-alpha.example.com/rest/v1/health           │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                        Monitoring & Observability                             │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  CloudWatch Logs                                                       │  │
│  │                                                                        │  │
│  │  Log Groups:                                                           │  │
│  │  ├─ /ecs/supabase                                                      │  │
│  │  │   - Kong Gateway logs                                               │  │
│  │  │   - Tenant Manager logs                                             │  │
│  │  │   - Studio logs                                                     │  │
│  │  │   - Functions Service logs                                          │  │
│  │  │                                                                    │  │
│  │  ├─ /aws/lambda/postgrest-{project_id}                                 │  │
│  │  │   - Per-tenant Lambda logs                                          │  │
│  │  │   - PostgREST query logs                                            │  │
│  │  │   - Bootstrap logs                                                  │  │
│  │  │                                                                    │  │
│  │  └─ /aws/rds/instance/{instance_id}/postgresql                         │  │
│  │      - PostgreSQL logs                                                 │  │
│  │      - Slow query logs                                                 │  │
│  │      - Error logs                                                      │  │
│  │                                                                        │  │
│  │  Log Queries:                                                          │  │
│  │  # Tail Kong logs (last 10 minutes)                                    │  │
│  │  aws logs tail /ecs/supabase --since 10m --region us-east-1            │  │
│  │                                                                        │  │
│  │  # Filter Tenant Manager logs                                          │  │
│  │  aws logs tail /ecs/supabase --since 5m \                              │  │
│  │    --filter-pattern "tenant-manager" --region us-east-1                │  │
│  │                                                                        │  │
│  │  # Lambda logs for specific project                                    │  │
│  │  aws logs tail /aws/lambda/postgrest-project-alpha \                   │  │
│  │    --since 5m --region us-east-1                                       │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  CloudWatch Metrics                                                    │  │
│  │                                                                        │  │
│  │  ECS Metrics:                                                          │  │
│  │  ├─ CPUUtilization (per service)                                       │  │
│  │  ├─ MemoryUtilization (per service)                                    │  │
│  │  ├─ RunningTaskCount                                                   │  │
│  │  └─ DesiredTaskCount                                                   │  │
│  │                                                                        │  │
│  │  Lambda Metrics:                                                       │  │
│  │  ├─ Invocations (per function)                                         │  │
│  │  ├─ Duration (p50, p99)                                                │  │
│  │  ├─ Errors                                                             │  │
│  │  ├─ Throttles                                                          │  │
│  │  └─ ConcurrentExecutions                                               │  │
│  │                                                                        │  │
│  │  RDS Metrics:                                                          │  │
│  │  ├─ DatabaseConnections                                                │  │
│  │  ├─ CPUUtilization                                                     │  │
│  │  ├─ FreeableMemory                                                     │  │
│  │  ├─ ReadLatency / WriteLatency                                         │  │
│  │  └─ FreeStorageSpace                                                   │  │
│  │                                                                        │  │
│  │  ALB Metrics:                                                          │  │
│  │  ├─ RequestCount                                                       │  │
│  │  ├─ TargetResponseTime                                                 │  │
│  │  ├─ HTTPCode_Target_2XX_Count                                          │  │
│  │  ├─ HTTPCode_Target_4XX_Count                                          │  │
│  │  └─ HTTPCode_Target_5XX_Count                                          │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  Health Checks                                                         │  │
│  │                                                                        │  │
│  │  ALB Target Health:                                                    │  │
│  │  ├─ Kong: GET /health (port 8000)                                      │  │
│  │  ├─ Tenant Manager: GET /health (port 8080)                            │  │
│  │  ├─ Studio: GET /api/health (port 8000)                                │  │
│  │  └─ Functions: GET /health (port 8080)                                 │  │
│  │                                                                        │  │
│  │  ECS Task Health:                                                      │  │
│  │  - Container health check (Docker HEALTHCHECK)                         │  │
│  │  - Interval: 30s                                                       │  │
│  │  - Timeout: 5s                                                         │  │
│  │  - Retries: 3                                                          │  │
│  │                                                                        │  │
│  │  RDS Health:                                                           │  │
│  │  - AWS managed health checks                                           │  │
│  │  - Automated backups                                                   │  │
│  │  - Multi-AZ failover (if enabled)                                      │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                        Deployment Checklist                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  Infrastructure Deployment:                                                   │
│  ☐ Update config.json with desired configuration                             │
│  ☐ Review CDK diff: cdk diff SupabaseStack                                   │
│  ☐ Deploy CDK stack: cdk deploy SupabaseStack                                │
│  ☐ Verify VPC, Security Groups, RDS, Redis created                           │
│  ☐ Verify ECS cluster and services running                                   │
│  ☐ Verify ALBs healthy and DNS resolving                                     │
│                                                                               │
│  Application Deployment:                                                      │
│  ☐ Build and push all images: ./build-and-push.sh all                        │
│  ☐ Force ECS service updates (if needed)                                     │
│  ☐ Verify all tasks running and healthy                                      │
│  ☐ Test Kong health: curl https://api.example.com/health                  │
│  ☐ Test Studio: curl https://studio.example.com/api/health                │
│                                                                               │
│  Database Setup:                                                              │
│  ☐ Run platform DB migrations (supabase_platform schema)                     │
│  ☐ Verify Kong DB initialized (migrations bootstrap)                         │
│  ☐ Test database connectivity from ECS tasks                                 │
│                                                                               │
│  Project Creation:                                                            │
│  ☐ Create test project via Studio or API                                     │
│  ☐ Verify Lambda function created                                            │
│  ☐ Verify Kong consumers registered                                          │
│  ☐ Verify tenant database created                                            │
│  ☐ Test API: curl https://test-project.example.com/rest/v1/               │
│                                                                               │
│  Monitoring Setup:                                                            │
│  ☐ Verify CloudWatch log groups created                                      │
│  ☐ Set up CloudWatch alarms (CPU, memory, errors)                            │
│  ☐ Configure log retention policies                                          │
│  ☐ Set up SNS notifications for critical alerts                              │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Deployment Architecture Key Points

1. **Infrastructure as Code**:
   - AWS CDK (TypeScript) manages all infrastructure
   - config.json serves as the single source of configuration
   - Version-controlled and repeatable deployments

2. **Containerized deployment**:
   - All services are containerized (Docker)
   - ECR serves as the private image registry
   - A unified build-and-push script

3. **Rolling updates**:
   - ECS performs automatic rolling updates
   - Zero-downtime deployments
   - Health checks ensure service availability

4. **Lambda management**:
   - Independent Lambda function per tenant
   - A unified image update process
   - Automatic configuration retrieval

5. **Monitoring and logging**:
   - Centralized log management via CloudWatch
   - Detailed metrics monitoring
   - Health checks and alerting

---

## Summary

This document showcases the complete architecture of the Supabase-on-AWS project from 7 different perspectives:

1. **Overall System Architecture**: Shows the overall system layout and component relationships
2. **Network and Infrastructure Architecture**: Detailed VPC, subnet, and security group configuration
3. **Request Flow Architecture**: The complete request chain for Gateway JWT Minting
4. **Data Flow Architecture**: Separation and flow of platform data vs. tenant data
5. **Service Component Architecture**: Responsibilities and communication of each microservice
6. **Security Architecture**: Detailed design of the 5-layer security protection
7. **Deployment Architecture**: CI/CD process and operational practices

### Architecture Highlights

- **Multi-tenant isolation**: Three-layer isolation across database, Lambda, and network ensures tenant security
- **Gateway JWT Minting**: An innovative authentication pattern that balances security and usability
- **Infrastructure as Code**: AWS CDK delivers repeatable, auditable infrastructure
- **Microservices architecture**: Loosely-coupled service design, easy to scale and maintain
- **Defense in Depth**: 5 layers of security protection ensure system security

### Technology Stack

- **Infrastructure**: AWS (VPC, ECS Fargate, Lambda, RDS, ElastiCache, ALB)
- **API Gateway**: Kong 3.5 (Lua/OpenResty)
- **Backend services**: TypeScript (Node.js, Fastify)
- **Database**: PostgreSQL 16.6
- **Cache**: Redis
- **Frontend**: React + Next.js (Studio)
- **IaC**: AWS CDK (TypeScript)
- **Containers**: Docker + ECR

### Scalability Considerations

- **Horizontal scaling**: ECS services can increase desired count
- **Vertical scaling**: Adjust CPU/Memory configuration
- **Database scaling**: Add more Worker RDS instances
- **Lambda scaling**: Automatic concurrency scaling
- **Cache scaling**: Redis cluster mode

### Future Improvement Directions

1. **Authentication service**: Integrate GoTrue (Supabase Auth)
2. **Storage service**: Integrate Supabase Storage
3. **Realtime service**: Integrate Supabase Realtime
4. **Connection pooling**: Integrate Supavisor (PostgreSQL connection pooler)
5. **Multi-region deployment**: Cross-region high availability
6. **Auto scaling**: Load-based automatic scaling
7. **Cost optimization**: Spot instances, Reserved instances

---

**Document Version**: v1.0.0  
**Last Updated**: 2026-02-25  
**Maintainer**: DevOps Team
