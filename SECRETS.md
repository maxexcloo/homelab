# Required Secrets Configuration

This project uses minimal secrets to maintain security while keeping configuration simple.

## Local Development (.mise.local.toml)

Only two secrets are required locally:

```toml
[env]
# 1Password Service Account Token
OP_SERVICE_ACCOUNT_TOKEN = "ops_..."

# HCP Terraform Token
TF_TOKEN_app_terraform_io = "..."
```

### How to obtain these secrets:

1. **OP_SERVICE_ACCOUNT_TOKEN**
   - Go to https://my.1password.com/integrations/active
   - Create a service account with access to Infrastructure and Services vaults
   - Copy the token (starts with `ops_`)

2. **TF_TOKEN_app_terraform_io**
   - Go to https://app.terraform.io/settings/tokens
   - Create a new API token
   - Copy the token value

## GitHub Actions Secrets

Only two secrets are required in GitHub:

1. Go to Settings → Secrets and variables → Actions
2. Add these repository secrets:
   - `OP_SERVICE_ACCOUNT_TOKEN`
   - `TF_TOKEN_app_terraform_io`

## Non-Sensitive Configuration

All other configuration is stored in version control:

- **infrastructure/terraform.auto.tfvars** - Infrastructure settings
- **infrastructure/dns.auto.tfvars** - DNS zones and records
- **services/terraform.auto.tfvars** - Service defaults

## Security Notes

- Never commit `.mise.local.toml` 
- All other provider credentials are stored in 1Password
- The service account token only has access to specific vaults
- HCP Terraform manages state securely with encryption at rest