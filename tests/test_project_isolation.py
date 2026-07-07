#!/usr/bin/env python3
"""
Verify that deleting Project A does not affect function calls in Project B
"""

import os
import sys
import requests
import json
import time
import subprocess
from urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import BASE_DOMAIN, ALB_DOMAIN

STUDIO_ALB = os.getenv("STUDIO_ALB", f"https://{ALB_DOMAIN}")
SUPABASE_DOMAIN = BASE_DOMAIN

def get_admin_api_key():
    result = subprocess.run(
        ['aws', 'secretsmanager', 'get-secret-value', 
         '--secret-id', 'supabase/admin-api-key',
         '--region', 'us-east-1',
         '--query', 'SecretString',
         '--output', 'text'],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()

ADMIN_API_KEY = get_admin_api_key()

print("=" * 70)
print("Verify that deleting Project A does not affect Project B")
print("=" * 70)

# Create Project A
print("\n=== 1. Create Project A ===")
resp = requests.post(
    f"{STUDIO_ALB}/api/v1/projects",
    json={"name": f"test-project-a-{int(time.time())}"},
    verify=False, timeout=300  # nosec B501
)
assert resp.status_code == 201
project_a_ref = resp.json()['ref']
project_a_domain = f"https://{project_a_ref}.{SUPABASE_DOMAIN}"
print(f"✓ Project A: {project_a_ref}")

# Create Project B
print("\n=== 2. Create Project B ===")
resp = requests.post(
    f"{STUDIO_ALB}/api/v1/projects",
    json={"name": f"test-project-b-{int(time.time())}"},
    verify=False, timeout=300  # nosec B501
)
assert resp.status_code == 201
project_b_ref = resp.json()['ref']
project_b_domain = f"https://{project_b_ref}.{SUPABASE_DOMAIN}"
print(f"✓ Project B: {project_b_ref}")

print("\nWaiting for projects to be ready (30s)...")
time.sleep(30)

# Get Project A's API key
print("\n=== 3. Get Project A's API Key ===")
resp = requests.get(f"{STUDIO_ALB}/api/v1/projects/{project_a_ref}/api-keys", verify=False)  # nosec B501
assert resp.status_code == 200
anon_key_a = next(k['api_key'] for k in resp.json() if k['name'] == 'anon')
print(f"✓ API Key A: {anon_key_a[:30]}...")

# Get Project B's API key
print("\n=== 4. Get Project B's API Key ===")
resp = requests.get(f"{STUDIO_ALB}/api/v1/projects/{project_b_ref}/api-keys", verify=False)  # nosec B501
assert resp.status_code == 200
anon_key_b = next(k['api_key'] for k in resp.json() if k['name'] == 'anon')
print(f"✓ API Key B: {anon_key_b[:30]}...")

# Deploy a function to Project A
print("\n=== 5. Deploy a function to Project A ===")
code_a = '''Deno.serve(() => {
  return new Response("Function from Project A")
})'''
files = {'file': ('index.ts', code_a, 'text/plain')}
resp = requests.post(
    f"{STUDIO_ALB}/api/v1/projects/{project_a_ref}/functions/deploy?slug=test-func-a",
    files=files, verify=False  # nosec B501
)
assert resp.status_code == 201
print("✓ Function A deployed successfully")

# Deploy a function to Project B
print("\n=== 6. Deploy a function to Project B ===")
code_b = '''Deno.serve(() => {
  return new Response("Function from Project B")
})'''
files = {'file': ('index.ts', code_b, 'text/plain')}
resp = requests.post(
    f"{STUDIO_ALB}/api/v1/projects/{project_b_ref}/functions/deploy?slug=test-func-b",
    files=files, verify=False  # nosec B501
)
assert resp.status_code == 201
print("✓ Function B deployed successfully")

print("\nWaiting for functions to be ready (10s)...")
time.sleep(10)

# Verify Project A's function is callable
print("\n=== 7. Verify Project A's function is callable ===")
resp = requests.get(
    f"{project_a_domain}/functions/v1/test-func-a",
    headers={"apikey": anon_key_a},
    verify=False  # nosec B501
)
assert resp.status_code == 200
assert "Project A" in resp.text
print(f"✓ Project A function call succeeded: {resp.text}")

# Verify Project B's function is callable
print("\n=== 8. Verify Project B's function is callable ===")
resp = requests.get(
    f"{project_b_domain}/functions/v1/test-func-b",
    headers={"apikey": anon_key_b},
    verify=False  # nosec B501
)
assert resp.status_code == 200
assert "Project B" in resp.text
print(f"✓ Project B function call succeeded: {resp.text}")

# Delete Project A
print("\n=== 9. Delete Project A ===")
headers = {"Authorization": f"Bearer {ADMIN_API_KEY}"}
resp = requests.delete(
    f"{STUDIO_ALB}/admin/v1/projects/{project_a_ref}",
    headers=headers, verify=False  # nosec B501
)
assert resp.status_code == 204
print("✓ Project A deleted successfully")

print("\nWaiting for cleanup to finish (10s)...")
time.sleep(10)

# Verify Project A's function is no longer callable
print("\n=== 10. Verify Project A's function is no longer callable ===")
resp = requests.get(
    f"{project_a_domain}/functions/v1/test-func-a",
    headers={"apikey": anon_key_a},
    verify=False  # nosec B501
)
if resp.status_code in [401, 404, 500, 503]:
    print(f"✓ Project A function is no longer callable ({resp.status_code})")
else:
    print(f"⚠ Project A function is still callable ({resp.status_code})")

# Verify Project B's function is still callable
print("\n=== 11. Verify Project B's function is still callable ===")
resp = requests.get(
    f"{project_b_domain}/functions/v1/test-func-b",
    headers={"apikey": anon_key_b},
    verify=False  # nosec B501
)
assert resp.status_code == 200, f"Project B function call failed: {resp.status_code} - {resp.text}"
assert "Project B" in resp.text
print(f"✓ Project B is still working normally: {resp.text}")

# Verify Project B's function list is normal
print("\n=== 12. Verify Project B's function list is normal ===")
resp = requests.get(f"{STUDIO_ALB}/api/v1/projects/{project_b_ref}/functions", verify=False)  # nosec B501
assert resp.status_code == 200
functions = resp.json()
assert len(functions) == 1
assert functions[0]['slug'] == 'test-func-b'
print(f"✓ Project B function list is normal: {[f['slug'] for f in functions]}")

# Clean up Project B
print("\n=== 13. Clean up Project B ===")
resp = requests.delete(
    f"{STUDIO_ALB}/admin/v1/projects/{project_b_ref}",
    headers=headers, verify=False  # nosec B501
)
assert resp.status_code == 204
print("✓ Project B deleted successfully")

print("\n" + "=" * 70)
print("✅ Verification complete! Deleting Project A did not affect Project B's function calls")
print("=" * 70)
