#!/usr/bin/env python3
"""
Create a properly formatted Firebase service account JSON file
"""

import json

# Firebase service account data with properly formatted private key
service_account = {
    "type": "service_account",
    "project_id": "drishti-link",
    "private_key_id": "01c48767aad13c82228ccdbc49c5d73b1d5a5d8b",
    "private_key": """-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDG6EAAg4yq5PUL
mfBpe7D8zdUr+SIrtjLGXvGV9bw00FneIKopcmNueAuFrYf0Lfr3haDE0YHSq5tH
wYyvGUVsoYtvpdeqD3NzqxEnz+GsiIOMmHY5EXoE9ydITUidwUnsaXGkB3Re/sxP
nNGgpepeQK54DMBjMGnG0rgwUY/28MPdc1T2dnd5Mv+22pvV461KeGmUcjfAOMl3
/rdXnfiZQ+yobjzoz6YquM5sj2BrMWg85E+LNXaCi41UDXxwOnjT0RRezmfr1L+r
RZVCVZy1pTws5zCtLMKJiiRYR18s7R/SPkXhmOxIaNomfzd5/qKwui9njP6N+/Fb
nfagSwWX9AgMBAAECggEAIdx0VtIOPqKDD9JJQd/Peb39qgJ7vXbDLo+Hr4h5nYER
p3Wmmi8xu6LejUeFIz23oW8jdxYWdHuHz/+kWEOkVLGsl9li/T2roReQcFdcmv9T
a7ohuCXgQJulmZKkh8yZrdAmiy7Esg5M0EnJSwCrxRdcTC4Zi1k4zKLfPcSIzlgS
G8CrVpwzVzZeKAiQccaUiRbKtuS4cdBAgHj21RygnYhawTytewvP/pVDbAMtJfZ0
/XsBH5ZAYK1DGJzUKhcE8rqRoDEDIyrWcn8dLtU3nn5DAtj9zTtPju7MQaVdEI0t
anqSqW03AgfCVV/BHfjfcvVp9coX58kPNPLeCin5EQKBgQDmA/PHmNpICLRXt0QQ
h6QxJGAmtv+6rdvQ8hx5HDshgAMMBanmKJ0fOBKS4v9IytZiE3Dntq19h+EBHvE9
Ea1rqxfitWcMIamo4GbEkMbBa7nQO2XqpVkbgHavnowVBKeFCPqb5ezHm0I34983
+LddCyOSufuOVWCf9MqhR3yMEQKBgQDdYKXo4N1YvPCBLSuj8oQbyjxEgFuZILvy
jsO5VwT5tWlTAb2vcrtFevPhgN05+o2KS+R62CpJMAvZPrWJN2PMwBoUfGjh9IPo
zqevFcOwtryhIoXUoh91ZfDVDB2Vncnqk5JOrR1gVd7hPkfOaEj0Y2kCW4BcvLqp
e+ZFORNXLQKBgQCiuGsOahEJ4raKU0kglITQixZGbTGuw+38/DquZw1h3qjJKXyP
KW42NrnVFidZPL27NluqYO6NHsJLw7MP6+COicRlCsXyrCHVKaMqLe2dyfLy4AJy
pDTMou3TwcsB14AXOknoXhlLAIgw99DjTN2TQh0RYOcYQ0gPAOMUg3kVsQKBgAtD
DW2pctk+02Ve7OdsQPhA84vwk7hYh/cw+BgHq0MgzXjhj8rLJWfFd36zVY3Lh0PP
1JHDSXNrtE6a+BVA8hzKcQk1wwgrrkI7sSAhFVF6GmKAJRrKHJuWUggkk6S24DzE
wR6rg+EQvUPsLS788ykrnX33NbKCD2Tr3q0K2EcJAoGANPmiLKPfIN7GQQbK2HOL
YfmRtObBa9Z86zFHu7B2ZQETGQMC4J6WHWEBnh0q3Q60sDWitLOimivNt4fVJyOC
Iws5FtmY5AhEj24xDpGvKjCehxkzrvxeATBvCGCO5KG8UiH0RvML87cTtXOD/bUA
VVZyW/m3F2c83GxGjLHVEC0=
-----END PRIVATE KEY-----""",
    "client_email": "firebase-adminsdk-fbsvc@drishti-link.iam.gserviceaccount.com",
    "client_id": "118261989230431318219",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-fbsvc%40drishti-link.iam.gserviceaccount.com",
    "universe_domain": "googleapis.com"
}

# Write to file
with open('firebase-service-account.json', 'w') as f:
    json.dump(service_account, f, indent=2)

print("✅ Created firebase-service-account.json")
print("📝 File should be properly formatted with correct newlines in private key")
