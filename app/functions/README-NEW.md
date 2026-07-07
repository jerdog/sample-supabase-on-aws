# Supabase Edge Functions Service

The official Supabase Edge Runtime deployed on AWS ECS, supporting Deno function invocation via HTTP and the Supabase SDK.

## Features

- ✅ **Official Runtime**: Uses `public.ecr.aws/supabase/edge-runtime:v1.69.28`
- ✅ **EFS Persistence**: Function files are stored on EFS and persist across container restarts
- ✅ **Dynamic Loading**: The main service router dynamically loads functions
- ✅ **SDK Compatible**: Fully compatible with the Supabase JS SDK
- ✅ **Kong Integration**: Routing and CORS support via Kong Gateway
- ✅ **Service Discovery**: Automatic service discovery via AWS Cloud Map

## Quick Start

### Deploy the Service

```bash
cd /Users/yonghs/Downloads/supabase-on-aws-main/app/functions
./deploy.sh
```

### Add a New Function

1. Create the function file `my-function.ts`:

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve((req) => {
  return new Response(
    JSON.stringify({message: 'My custom function!'}),
    {headers: {'Content-Type': 'application/json'}}
  )
})
```

2. Deploy the function:

```bash
./add-function.sh my-function ./my-function.ts
```

### Test the Function

```bash
# Direct call
curl https://project-alpha.example.com/functions/my-function

# SDK path
curl https://project-alpha.example.com/functions/v1/my-function
```

## Using the Supabase SDK

```javascript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://project-alpha.example.com',
  'YOUR_ANON_KEY'
)

// Call the function
const { data, error } = await supabase.functions.invoke('my-function', {
  body: { name: 'World' }
})

console.log(data)
```

## Architecture

```
Client → ALB → Kong Gateway → Functions Service (ECS)
                                    ↓
                              Main Service (router)
                                    ↓
                              EFS (/home/deno/functions)
                                    ├─ main/
                                    ├─ hello/
                                    └─ your-function/
```

## Directory Structure

```
app/functions/
├── deploy.sh              # Deployment script
├── add-function.sh        # Add-function script
├── DEPLOYMENT.md          # Detailed deployment documentation
└── README.md              # This file
```

## Tech Stack

- **Runtime**: Deno (Supabase Edge Runtime)
- **Image**: `public.ecr.aws/supabase/edge-runtime:v1.69.28`
- **Storage**: AWS EFS
- **Networking**: AWS Cloud Map
- **Gateway**: Kong Gateway
- **Compute**: ECS Fargate (256 CPU, 512 MB)

## Endpoints

- **Health**: `https://project-alpha.example.com/functions/health`
- **Functions**: `https://project-alpha.example.com/functions/v1/{function-name}`

## Monitoring

```bash
# View logs
aws logs tail /ecs/supabase --since 10m --filter-pattern functions-service --region us-east-1

# Check service status
aws ecs describe-services --cluster <ECS_CLUSTER> --services functions-service --region us-east-1
```

## Documentation

For detailed deployment and troubleshooting documentation, see [DEPLOYMENT.md](./DEPLOYMENT.md)

## Example Functions

### Hello World

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve((req) => {
  return new Response(
    JSON.stringify({message: 'Hello from Supabase!'}),
    {headers: {'Content-Type': 'application/json'}}
  )
})
```

### Function with Parameters

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  const { name } = await req.json()
  
  return new Response(
    JSON.stringify({
      message: `Hello, ${name || 'World'}!`,
      timestamp: new Date().toISOString()
    }),
    {headers: {'Content-Type': 'application/json'}}
  )
})
```

## License

MIT
