#!/usr/bin/env python3
"""
Fix Firebase service account JSON with proper formatting
"""

import json
import base64

# Read the current .env to extract the base64 string
with open('.env', 'r') as f:
    env_content = f.read()

# Extract the base64 string
for line in env_content.split('\n'):
    if line.startswith('FIREBASE_SERVICE_ACCOUNT_JSON='):
        b64_str = line.split('=', 1)[1]
        break
else:
    print("❌ FIREBASE_SERVICE_ACCOUNT_JSON not found in .env")
    exit(1)

# Decode and fix the JSON
try:
    json_bytes = base64.b64decode(b64_str)
    service_account = json.loads(json_bytes)
    
    # Fix the private key by ensuring proper newlines
    if 'private_key' in service_account:
        pk = service_account['private_key']
        # Replace literal \n with actual newlines
        pk = pk.replace('\\n', '\n')
        service_account['private_key'] = pk
    
    # Re-encode
    fixed_json_bytes = json.dumps(service_account).encode('utf-8')
    fixed_b64 = base64.b64encode(fixed_json_bytes).decode('utf-8')
    
    # Update .env
    lines = env_content.split('\n')
    new_lines = []
    for line in lines:
        if line.startswith('FIREBASE_SERVICE_ACCOUNT_JSON='):
            new_lines.append(f'FIREBASE_SERVICE_ACCOUNT_JSON={fixed_b64}')
        else:
            new_lines.append(line)
    
    with open('.env', 'w') as f:
        f.write('\n'.join(new_lines))
    
    print("✅ Fixed FIREBASE_SERVICE_ACCOUNT_JSON in .env")
    print(f"📝 New base64 length: {len(fixed_b64)}")
    
    # Test decode
    test_bytes = base64.b64decode(fixed_b64)
    test_json = json.loads(test_bytes)
    print(f"✅ Test decode successful, project_id: {test_json['project_id']}")
    
except Exception as e:
    print(f"❌ Error fixing Firebase JSON: {e}")
    exit(1)
