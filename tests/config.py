"""
Test configuration file
Contains all configuration and constants required by the tests
"""

import json
import os

# ============================================
# Read configuration from the root config.json (single source of truth)
# ============================================
_config_path = os.path.join(os.path.dirname(__file__), '..', 'config.json')
with open(_config_path) as _f:
    _global_config = json.load(_f)

# ============================================
# Base configuration
# ============================================

# Domain configuration
BASE_DOMAIN = _global_config["domain"]["baseDomain"]
ALB_DOMAIN = os.getenv("ALB_DOMAIN", "")

# AWS configuration
AWS_REGION = _global_config["project"]["region"]
AWS_ACCOUNT_ID = _global_config["project"]["accountId"]
ECS_CLUSTER = _global_config["infraStack"]["cluster"]["name"]

# ============================================
# Service configuration
# ============================================

# List of supported services
SERVICES = {
    "kong-gateway": {
        "ecs_service": "kong-gateway",
        "health_endpoint": "/health",
        "port": 8000,
    },
    "functions": {
        "ecs_service": "functions-service",
        "health_endpoint": "/health",
        "path_prefix": "/functions",
        "port": 8080,
    },
    "postgrest": {
        "path_prefix": "/rest/v1",
        "test_endpoints": [
            "/",  # OpenAPI docs
        ],
    },
}

# ============================================
# Test project configuration
# ============================================

# List of test projects (for multi-tenant testing)
# All projects route to the postgrest-test-sdk-jwt Lambda
# JWT issued using test-sdk-jwt's jwt_secret, ref=project-alpha
TEST_PROJECTS = [
    {
        "id": "project-alpha",
        "subdomain": f"project-alpha.{BASE_DOMAIN}",
        "anon_key": "<your-supabase-anon-key>",
        "service_role_key": "<your-supabase-service-role-key>",
    },
]

# ============================================
# Supabase configuration
# ============================================

# Supabase anon key (for SDK testing) — role=anon, signed with test-sdk-jwt secret
SUPABASE_ANON_KEY = os.getenv(
    "SUPABASE_ANON_KEY",
    "<your-supabase-anon-key>"
)

# Supabase Service Role Key (for admin operations) — role=service_role, signed with test-sdk-jwt secret
SUPABASE_SERVICE_ROLE_KEY = os.getenv(
    "SUPABASE_SERVICE_ROLE_KEY",
    "<your-supabase-service-role-key>"
)

# ============================================
# Timeout and performance configuration
# ============================================

# Timeout configuration (seconds)
TIMEOUTS = {
    "connection": 5,
    "read": 30,
    "health_check": 10,
}

# Performance benchmarks
PERFORMANCE_BENCHMARKS = {
    "health_check": 5000,  # ms
    "api_response": 2000,  # ms
}

# Retry configuration
RETRY_CONFIG = {
    "max_attempts": 3,
    "backoff_factor": 2,
    "retry_statuses": [500, 502, 503, 504],
}

# ============================================
# Helper functions
# ============================================

def get_alb_url(path: str = "") -> str:
    """Get the ALB URL"""
    return f"https://{ALB_DOMAIN}{path}"

def get_subdomain_url(project_id: str, path: str = "") -> str:
    """Get the subdomain URL"""
    return f"https://{project_id}.{BASE_DOMAIN}{path}"

def get_service_url(service_name: str, use_alb: bool = True) -> str:
    """Get the service URL"""
    service = SERVICES.get(service_name, {})
    path = service.get("path_prefix", "")
    health = service.get("health_endpoint", "")

    if use_alb:
        return get_alb_url(path + health)
    else:
        # Use the subdomain of the first test project
        return get_subdomain_url(TEST_PROJECTS[0]["id"], path + health)


if __name__ == "__main__":
    # Test configuration
    print("=== Test configuration verification ===")
    print(f"Base Domain: {BASE_DOMAIN}")
    print(f"ALB Domain: {ALB_DOMAIN}")
    print(f"AWS Region: {AWS_REGION}")
    print(f"\nServices:")
    for service_name in SERVICES.keys():
        print(f"  - {service_name}")
    print(f"\nTest projects:")
    for project in TEST_PROJECTS:
        print(f"  - {project['id']}: {project['subdomain']}")
