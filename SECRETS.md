# Secrets Setup

## Required Secrets

### 1. Local Development

Create `.mise.local.toml`:
```toml
[env]
OP_SERVICE_ACCOUNT_TOKEN = "ops_..."     # 1Password service account
TF_TOKEN_app_terraform_io = "..."        # HCP Terraform token
```

**Get 1Password token:**
1. Go to https://my.1password.com/integrations/active
2. Create service account with vault access
3. Copy token

**Get HCP Terraform token:**
1. Go to https://app.terraform.io/settings/tokens
2. Create API token
3. Copy token

### 2. GitHub Actions

Add same tokens as repository secrets in Settings → Secrets.

### 3. Provider Credentials

Run `mise run setup` to create providers entry, then add:

```yaml
Name: providers
Vault: Homelab

Sections:
  b2:
    application_key: "..."        # From Backblaze → App Keys
    application_key_id: "..."
    
  cloudflare:
    account_id: "..."            # From dashboard sidebar
    api_token: "..."             # Create with DNS edit permissions
    
  hcp:
    organization: "..."          # HCP Terraform org
    workspace: "homelab"         # Workspace name
    
  resend:
    api_key: "re_..."            # From Resend → API Keys
    domain: "example.com"        # Verified domain
    
  tailscale:
    api_key: "tskey-api-..."     # From Settings → Keys
    tailnet: "example.com"       # Your tailnet name
```

## Auto-Generated Secrets

These are created automatically per server:

- `b2_*` - Backup credentials
- `cloudflare_*` - Tunnel and API tokens
- `resend_api_key` - Email API key
- `tailscale_*` - Auth keys and IPs

## Secret Rotation

### Automatic
- Tailscale keys: Renewed 30 days before expiry

### Manual
```bash
# Regenerate Cloudflare tunnel
tofu apply -replace='cloudflare_zero_trust_tunnel_cloudflared.homelab["server-name"]'

# Rotate Tailscale key
tofu apply -target='tailscale_tailnet_key.homelab["server-name"]'
```

## Troubleshooting

```bash
# Check token
echo $OP_SERVICE_ACCOUNT_TOKEN

# Test 1Password
op vault list

# Verify provider credentials
op item get providers --vault="Homelab"
```
