import json, base64
from cryptography.hazmat.primitives.serialization import load_pem_private_key

j = json.load(open('firebase-service-account.json'))
pk = j['private_key'].replace('\\n','\n')

# Try fixing padding
pk_fixed = pk.replace('EC0=\n', 'EC0==\n')
print("Original len without newlines:", len(pk.replace('\n', '').replace('-----BEGIN PRIVATE KEY-----', '').replace('-----END PRIVATE KEY-----', '')))
print("Fixed len without newlines:", len(pk_fixed.replace('\n', '').replace('-----BEGIN PRIVATE KEY-----', '').replace('-----END PRIVATE KEY-----', '')))

try:
    key = load_pem_private_key(pk_fixed.encode(), password=None)
    print('LOADED KEY WITH APPENDED == !')
except Exception as e:
    print('ERROR:', e)
