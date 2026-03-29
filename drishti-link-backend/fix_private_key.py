#!/usr/bin/env python3
"""
Fix the private key in the Firebase service account JSON
"""

import json

# Read the current JSON
with open('firebase-service-account.json', 'r') as f:
    service_account = json.load(f)

# Fix the private key by converting \n to actual newlines
if 'private_key' in service_account:
    pk = service_account['private_key']
    # Convert escaped newlines to actual newlines
    pk = pk.replace('\\n', '\n')
    service_account['private_key'] = pk

# Write back with proper formatting
with open('firebase-service-account.json', 'w') as f:
    json.dump(service_account, f, indent=2)

print("✅ Fixed private key newlines in firebase-service-account.json")

# Verify the fix
with open('firebase-service-account.json', 'r') as f:
    content = f.read()
    if '\\n' in content:
        print("❌ Still has escaped newlines")
    else:
        print("✅ Private key has actual newlines")
