#!/usr/bin/env python3
"""
Setup script to extract Firebase service account JSON from secrets file
and add base64 encoded version to .env
"""

import json
import base64
import os

def extract_firebase_json():
    """Extract Firebase service account JSON from drishti_secrets.txt"""
    secrets_path = '../drishti_secrets.txt'
    
    with open(secrets_path, 'r') as f:
        content = f.read()
    
    # Find the JSON section
    lines = content.split('\n')
    json_start = None
    json_end = None
    
    for i, line in enumerate(lines):
        if line.strip().startswith('FIREBASE_SERVICE_ACCOUNT_JSON:'):
            json_start = i
        if json_start is not None and line.strip() == '}' and 'universe_domain' in line:
            json_end = i
            break
    
    if json_start is None or json_end is None:
        raise ValueError("Could not find Firebase service account JSON in secrets file")
    
    # Extract JSON lines and fix escaping
    json_lines = []
    for i in range(json_start, json_end + 1):
        line = lines[i]
        # Remove the prefix if it's the first line
        if i == json_start and 'FIREBASE_SERVICE_ACCOUNT_JSON:' in line:
            line = line.split('FIREBASE_SERVICE_ACCOUNT_JSON:')[1].strip()
        
        # Fix escaped newlines in private key
        if '\\n' in line and 'private_key' in line:
            line = line.replace('\\\\n', '\\n')
        
        json_lines.append(line)
    
    json_str = '\n'.join(json_lines)
    
    # Parse and validate JSON
    service_account = json.loads(json_str)
    
    return service_account

def update_env_file():
    """Update .env file with base64 encoded Firebase JSON"""
    # Get the service account JSON
    service_account = extract_firebase_json()
    
    # Encode to base64
    json_bytes = json.dumps(service_account).encode('utf-8')
    b64_encoded = base64.b64encode(json_bytes).decode('utf-8')
    
    # Read current .env
    env_path = '.env'
    with open(env_path, 'r') as f:
        env_content = f.read()
    
    # Add Firebase service account JSON
    new_line = f'FIREBASE_SERVICE_ACCOUNT_JSON={b64_encoded}'
    
    # Check if it already exists
    if 'FIREBASE_SERVICE_ACCOUNT_JSON=' in env_content:
        # Replace existing line
        lines = env_content.split('\n')
        for i, line in enumerate(lines):
            if line.startswith('FIREBASE_SERVICE_ACCOUNT_JSON='):
                lines[i] = new_line
                break
        env_content = '\n'.join(lines)
    else:
        # Add to end
        env_content += f'\n{new_line}\n'
    
    # Write back to .env
    with open(env_path, 'w') as f:
        f.write(env_content)
    
    print(f"✅ Added FIREBASE_SERVICE_ACCOUNT_JSON to .env")
    print(f"📝 Base64 encoded length: {len(b64_encoded)} characters")

if __name__ == "__main__":
    try:
        update_env_file()
        print("✅ Firebase setup completed successfully")
    except Exception as e:
        print(f"❌ Error: {e}")
        exit(1)
