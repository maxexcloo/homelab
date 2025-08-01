# Required Secrets Configuration

This project uses minimal secrets to maintain security while keeping configuration simple.

## Local Development (.mise.local.toml)

Only three secrets are required locally:

```toml
[env]
# 1Password Service Account Token
OP_SERVICE_ACCOUNT_TOKEN = "ops_..."

# B2 State Backend Credentials  
AWS_ACCESS_KEY_ID = "0021..."
AWS_SECRET_ACCESS_KEY = "K002..."
```

### How to obtain these secrets:

1. **OP_SERVICE_ACCOUNT_TOKEN**
   - Go to https://my.1password.com/integrations/active
   - Create a service account with access to Infrastructure and Services vaults
   - Copy the token (starts with `ops_`)

2. **AWS_ACCESS_KEY_ID & AWS_SECRET_ACCESS_KEY**
   - These are Backblaze B2 credentials for Terraform state
   - Create app keys: `b2 create-key --bucket homelab-terraform-state terraform-state listBuckets,readFiles,writeFiles,deleteFiles`
   - Use the keyID and applicationKey values

## GitHub Actions Secrets

The same three secrets are required in GitHub:

1. Go to Settings → Secrets and variables → Actions
2. Add these repository secrets:
   - `OP_SERVICE_ACCOUNT_TOKEN`
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

## Non-Sensitive Configuration

All other configuration is stored in version control:

- **infrastructure/terraform.auto.tfvars** - Infrastructure settings
- **infrastructure/dns.auto.tfvars** - DNS zones and records
- **services/terraform.auto.tfvars** - Service defaults

## Security Notes

- Never commit `.mise.local.toml` 
- All other provider credentials are stored in 1Password
- The service account token only has access to specific vaults
- B2 credentials are scoped to the state bucket only