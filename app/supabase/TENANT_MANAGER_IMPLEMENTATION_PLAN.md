# Multi-Tenant Project Creation Feature Implementation Plan

## Overview

Implement a multi-tenant project creation feature in the Supabase apps project, using a frontend/backend-separated architecture:
- **Backend**: A standalone Tenant Manager Service
- **Frontend**: Extend the management UI within Studio
- **SDK**: Call the Admin Service API directly

---

## Architecture Design

```
┌─────────────────┐     ┌─────────────────┐
│  Studio Frontend │     │    SDK/CLI      │
│  (management UI) │     │ (programmatic)  │
└────────┬────────┘     └────────┬────────┘
         │                       │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │  Tenant Manager       │
         │  Service (Node.js)    │
         │  /admin/v1/projects   │
         └───────────┬───────────┘
                     │
     ┌───────────────┼───────────────┐
     ▼               ▼               ▼
┌─────────┐   ┌───────────┐   ┌───────────┐
│ RDS Cluster│ │ DynamoDB  │   │ Secrets   │
│         │   │           │   │ Manager   │
└─────────┘   └───────────┘   └───────────┘
```

---

## Part 1: Tenant Manager Service (Backend)

### 1.1 Project Structure

```
apps/tenant-manager/
├── src/
│   ├── index.ts                    # Entry point
│   ├── config/
│   │   └── index.ts               # Environment variable configuration
│   ├── routes/
│   │   ├── index.ts               # Route aggregation
│   │   ├── projects.ts            # Project CRUD API
│   │   ├── health.ts              # Health check
│   │   └── admin.ts               # Admin endpoints
│   ├── services/
│   │   ├── project-service.ts     # Project service (migrated from Studio)
│   │   ├── rds-balancer.ts        # RDS load balancing
│   │   ├── schema-initializer.ts  # Schema initialization
│   │   ├── key-generator.ts       # Key generation
│   │   └── verifier.ts            # Project verification
│   ├── aws/
│   │   ├── secrets-manager.ts     # AWS Secrets Manager
│   │   ├── dynamodb.ts            # DynamoDB operations
│   │   └── rds.ts                 # RDS instance management
│   ├── db/
│   │   ├── postgres.ts            # PostgreSQL connection pool
│   │   └── queries.ts             # SQL queries
│   ├── middleware/
│   │   ├── auth.ts                # Authentication middleware
│   │   └── validation.ts          # Parameter validation
│   └── types/
│       └── index.ts               # Type definitions
├── package.json
├── tsconfig.json
└── Dockerfile
```

### 1.2 API Endpoint Design (compatible with the official Management API)

**Core project endpoints** (matching the official format):

| Method | Endpoint | Description |
|------|------|------|
| POST | `/admin/v1/projects` | Create project |
| GET | `/admin/v1/projects` | List all projects (paginated) |
| GET | `/admin/v1/projects/{ref}` | Get project details |
| PATCH | `/admin/v1/projects/{ref}` | Update project |
| DELETE | `/admin/v1/projects/{ref}` | Delete project |
| POST | `/admin/v1/projects/{ref}/pause` | Pause project |
| POST | `/admin/v1/projects/{ref}/restore` | Restore project |
| GET | `/admin/v1/projects/{ref}/health` | Health check |

**RDS instance management endpoints**:

| Method | Endpoint | Description |
|------|------|------|
| GET | `/admin/v1/rds-instances` | List all RDS instances |
| POST | `/admin/v1/rds-instances` | Add a new RDS instance |
| GET | `/admin/v1/rds-instances/{id}` | Get RDS instance details |
| PATCH | `/admin/v1/rds-instances/{id}` | Update RDS instance configuration |
| DELETE | `/admin/v1/rds-instances/{id}` | Remove an RDS instance |
| GET | `/admin/v1/rds-instances/{id}/metrics` | RDS instance metrics |
| GET | `/admin/v1/rds-instances/{id}/projects` | List of projects on the instance |
| POST | `/admin/v1/rds-instances/{id}/drain` | Set the instance to draining (stop assigning new projects) |

### 1.3 Request/Response Formats (compatible with the official API)

**Create project request**:
```typescript
interface CreateProjectRequest {
  name: string                           // Project name
  organization_id?: number               // Organization ID
  db_pass?: string                       // Database password (optional, auto-generated)
  db_region?: string                     // Region (the system automatically picks the least-loaded RDS in this region)
  desired_instance_size?: InstanceSize   // Instance size
  postgres_engine?: '15' | '17'          // PG version
  admin_email?: string                   // Admin email
  plan?: 'free' | 'pro' | 'team'         // Plan type
}
// Note: the RDS instance is automatically selected by the system; manual selection is not supported
```

**Create project response** (matching the official format):
```typescript
interface CreateProjectResponse {
  id: number
  ref: string                            // Project reference ID
  name: string
  organization_id: number
  cloud_provider: string
  region: string
  status: ProjectStatus
  endpoint: string                       // API endpoint URL
  anon_key: string                       // Anonymous key
  service_key: string                    // Service role key
  inserted_at: string
  // Multi-tenant extension fields
  db_instance_id: number                 // The RDS instance it resides on
  schema_name: string                    // Schema name
}
```

**Project status enum** (matching the official API):
```typescript
type ProjectStatus =
  | 'ACTIVE_HEALTHY'
  | 'COMING_UP'
  | 'GOING_DOWN'
  | 'INACTIVE'
  | 'INIT_FAILED'
  | 'REMOVED'
  | 'RESTORING'
  | 'PAUSING'
  | 'PAUSED'
  | 'RESTARTING'
```

**Pagination response format** (matching the official API):
```typescript
interface ListProjectsResponse {
  pagination: {
    count: number
    limit: number
    offset: number
  }
  projects: Project[]
}
```

### 1.4 RDS Instance Management Format

**Add RDS instance request**:
```typescript
interface AddRdsInstanceRequest {
  identifier: string               // Instance identifier (e.g. rds-prod-01)
  name: string                     // Display name
  host: string                     // Host address
  port: number                     // Port (default 5432)
  admin_user: string               // Admin username
  admin_password: string           // Admin password (stored encrypted)
  region: string                   // Region
  max_databases: number            // Maximum number of databases/schemas
  weight?: number                  // Weight (used for weighted random selection, default 1)
}
```

**RDS instance response**:
```typescript
interface RdsInstance {
  id: number
  identifier: string
  name: string
  host: string
  port: number
  region: string
  status: 'active' | 'draining' | 'maintenance' | 'offline'
  max_databases: number
  current_databases: number        // Current number of projects
  weight: number
  created_at: string
  updated_at: string
  // Metrics (optional; get details via the /metrics endpoint)
  metrics?: {
    cpu_usage: number
    connection_count: number
    storage_used_gb: number
  }
}
```

**Setting the Draining state**:
```typescript
// POST /admin/v1/rds-instances/{id}/drain
// Sets the instance to draining status; the system will no longer assign new projects to it
// Used when planning to decommission or perform maintenance on an RDS instance
interface DrainResponse {
  id: number
  status: 'draining'
  projects_count: number           // Number of projects still on this instance
  message: string                  // Informational message
}
```

### 1.5 RDS Auto-Selection Logic (fully automatic; users cannot manually specify)

**Selection strategy**:
```typescript
type InstanceSelectionStrategy =
  | 'least_projects'      // Fewest projects (default)
  | 'least_connections'   // Fewest connections
  | 'weighted_random'     // Weighted random
  | 'region_affinity'     // Region affinity (prefer the RDS in the same region as the request)
```

**Load scoring algorithm**:
```javascript
calculateScore({ schemaCount, cpuUsage, connectionCount, maxSchemas }) {
  return (
    (schemaCount / maxSchemas) * 0.4 +        // Schema count: 40%
    (cpuUsage / 100) * 0.3 +                  // CPU usage: 30%
    (connectionCount / 500) * 0.2 +           // Connection count: 20%
    (1 - (maxSchemas - schemaCount) / maxSchemas) * 0.1
  )
}
```

**Workflow**:
1. When creating a project, the system automatically queries all RDS instances with `status: 'active'`
2. Excludes instances with `status: 'draining'` or `status: 'offline'`
3. If `db_region` is specified, prefer RDS instances in that region
4. Use the load scoring algorithm to select the instance with the lowest score
5. Assign the project to the selected RDS instance

### 1.6 Core Logic Migrated from Studio

**Source file locations** (Studio):
- `lib/api/self-hosted/multi-tenant/transaction-manager.ts` → Project creation/deletion transactions
- `lib/api/self-hosted/multi-tenant/database-provisioner.ts` → Database creation/initialization
- `lib/api/self-hosted/multi-tenant/crypto.ts` → Key generation
- `lib/api/self-hosted/multi-tenant/services/` → Service registration (Auth, Realtime, Supavisor)
- `lib/api/self-hosted/multi-tenant/types.ts` → Type definitions

**Enhancements after migration**:
1. Add AWS Secrets Manager integration
2. Add DynamoDB mapping table operations
3. Add RDS load-balancing selection
4. Add parameter validation (email, quota)
5. Enhance the rollback mechanism (including AWS resource cleanup)

### 1.7 Project Creation Flow

```
1. Validate parameters
   - Check project_id uniqueness
   - Validate admin_email format
   - Check quota limits

2. Select RDS instance
   - Query load on all RDS instances
   - Use the load-balancing algorithm to select the best instance

3. Create schema
   - Create the project_xxx schema on the selected RDS
   - Create the base table structure
   - Set up RLS policies

4. Generate keys
   - jwt_secret, anon_key, service_role_key
   - Database password

5. Store keys
   - AWS Secrets Manager

6. Update mapping
   - DynamoDB project-rds-mapping

7. Register services
   - GoTrue (Auth)
   - Realtime
   - Supavisor

8. Verify creation
   - Test endpoint availability

9. Return result
   - project_id, endpoint, API keys
```

### 1.8 Key Implementation Files

**project-service.ts** - Core service
```typescript
// Main methods
export class ProjectService {
  async createProject(input: CreateProjectInput): Promise<CreateProjectResponse>
  async deleteProject(projectId: string): Promise<void>
  async getProject(projectId: string): Promise<Project>
  async listProjects(options: ListOptions): Promise<Project[]>
  async pauseProject(projectId: string): Promise<void>
  async resumeProject(projectId: string): Promise<void>
}
```

**rds-balancer.ts** - RDS load balancing
```typescript
export class RDSBalancer {
  async selectBestInstance(options?: SelectionOptions): Promise<RDSInstance>
  async getInstanceMetrics(instanceId: string): Promise<InstanceMetrics>
}
```

---

## Part 2: Studio Frontend Extension

### 2.1 New Pages

| Path | Description |
|------|------|
| `/admin/projects` | Project list (admin view) |
| `/admin/projects/new` | Create project |
| `/admin/projects/[ref]` | Project details |
| `/admin/rds-instances` | RDS instance management |

### 2.2 New Components

```
components/interfaces/Admin/
├── ProjectList/
│   ├── AdminProjectList.tsx       # Project list
│   ├── AdminProjectRow.tsx        # Project row
│   └── ProjectStatusBadge.tsx     # Status badge
├── ProjectCreation/
│   ├── AdminProjectForm.tsx       # Creation form (no RDS selection; the system assigns automatically)
│   └── ProjectQuotaInput.tsx      # Quota settings
└── RdsInstances/
    ├── RdsInstanceList.tsx        # RDS instance list
    ├── RdsInstanceMetrics.tsx     # Metrics display
    ├── AddRdsInstanceForm.tsx     # Form for adding a new RDS instance
    └── RdsInstanceActions.tsx     # Instance actions (drain, delete, etc.)
```

### 2.3 Data Layer

```
data/admin/
├── projects/
│   ├── admin-projects-query.ts        # Project list query
│   ├── admin-project-create-mutation.ts # Create project
│   └── admin-project-delete-mutation.ts # Delete project
├── rds-instances/
│   ├── rds-instances-query.ts         # RDS instance list query
│   ├── rds-instance-add-mutation.ts   # Add RDS instance
│   ├── rds-instance-update-mutation.ts # Update RDS instance
│   ├── rds-instance-delete-mutation.ts # Delete RDS instance
│   ├── rds-instance-drain-mutation.ts # Set draining status
│   └── rds-instance-metrics-query.ts  # RDS metrics query
└── types.ts                           # Type definitions
```

### 2.4 Reusable Existing Components

Reused from `components/interfaces/ProjectCreation/`:
- `ProjectNameInput.tsx`
- `RegionSelector.tsx`
- `DatabasePasswordInput.tsx`
- `OrganizationSelector.tsx`
- `SecurityOptions.tsx`

---

## Part 3: SDK Design

### 3.1 SDK Structure

```typescript
// @supabase/admin-sdk
import { AdminClient } from '@supabase/admin-sdk'

const admin = new AdminClient({
  endpoint: 'https://admin.example.com',
  apiKey: 'your-admin-api-key'
})

// Create project
const project = await admin.projects.create({
  name: 'my-project',
  region: 'us-east-1',
  plan: 'pro'
})

// List projects
const projects = await admin.projects.list()

// Delete project
await admin.projects.delete('project-id')
```

---

## Implementation Steps

### Phase 1: Tenant Manager Service Foundation

1. Initialize the project structure (`apps/tenant-manager/`)
2. Configure TypeScript, ESLint, and environment variables
3. Implement the Express/Fastify routing framework
4. Migrate the `transaction-manager.ts` logic
5. Migrate the `database-provisioner.ts` logic
6. Migrate the `crypto.ts` key generation logic

### Phase 2: AWS Integration

1. Implement the Secrets Manager module
2. Implement DynamoDB mapping operations
3. Implement the RDS load balancer
4. Add CloudWatch metrics retrieval

### Phase 3: API Completion

1. Implement all CRUD endpoints
2. Add authentication middleware
3. Add parameter validation
4. Implement the rollback mechanism
5. Add a health check endpoint

### Phase 4: Studio Frontend

1. Create the Admin layout and navigation
2. Implement the project list page
3. Implement the project creation form
4. Implement the RDS instance management page
5. Wire the data layer to the Admin Service

### Phase 5: Testing and Deployment

1. Unit tests
2. Integration tests
3. Docker image build
4. ECS deployment configuration
5. Documentation

---

## Environment Variables

### Tenant Manager Service

```bash
# Service configuration
PORT=3001
NODE_ENV=production

# AWS configuration
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=xxx
AWS_SECRET_ACCESS_KEY=xxx

# Secrets Manager
AWS_SECRETS_PREFIX=supabase/projects

# DynamoDB
DYNAMODB_TABLE_PROJECT_MAPPING=project-rds-mapping

# Default RDS
RDS_DEFAULT_INSTANCE_ID=1

# Authentication
ADMIN_API_KEY=xxx
JWT_SECRET=xxx

# Service registration
GOTRUE_URL=http://gotrue:9999
REALTIME_URL=http://realtime:4000
SUPAVISOR_URL=http://supavisor:4000
```

### Studio

```bash
# Admin Service configuration
NEXT_PUBLIC_ADMIN_SERVICE_URL=https://admin.example.com
ADMIN_SERVICE_API_KEY=xxx
```

---

## Key File Paths

### Source Files to Migrate (Studio)

- `/apps/studio/lib/api/self-hosted/multi-tenant/transaction-manager.ts`
- `/apps/studio/lib/api/self-hosted/multi-tenant/database-provisioner.ts`
- `/apps/studio/lib/api/self-hosted/multi-tenant/crypto.ts`
- `/apps/studio/lib/api/self-hosted/multi-tenant/types.ts`
- `/apps/studio/lib/api/self-hosted/multi-tenant/services/auth.ts`
- `/apps/studio/lib/api/self-hosted/multi-tenant/services/realtime.ts`
- `/apps/studio/lib/api/self-hosted/multi-tenant/services/supavisor.ts`

### Reusable Frontend Components (Studio)

- `/apps/studio/components/interfaces/ProjectCreation/ProjectNameInput.tsx`
- `/apps/studio/components/interfaces/ProjectCreation/RegionSelector.tsx`
- `/apps/studio/components/interfaces/ProjectCreation/DatabasePasswordInput.tsx`
- `/apps/studio/components/interfaces/ProjectCreation/OrganizationSelector.tsx`

---

## Verification Plan

1. **Unit tests**: Independent tests for each service module
2. **Integration tests**: Full project creation flow test
3. **End-to-end tests**:
   - Create a project via the SDK
   - Verify the database is accessible
   - Verify the API keys are valid
   - Verify service registration succeeded
4. **Rollback tests**: Simulate failure scenarios to verify rollback completeness
