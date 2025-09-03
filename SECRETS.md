# Secrets Setup

## Auto-Generated Secrets

These are created automatically per server:

- `age_*` - SOPS encryption keypairs for docker-compose secrets
- `b2_*` - Backup credentials
- `cloudflare_*` - Tunnel and API tokens
- `resend_api_key` - Email API key
- `tailscale_*` - Auth keys and IPs

## Required Secrets

### 1. Local Development

Run `mise run setup` to create `.mise.local.toml`, then update:

**Get 1Password token:**
1. Go to https://my.1password.com/integrations/active
2. Create service account with vault access

**Get HCP Terraform token:**
1. Go to https://app.terraform.io/settings/tokens
2. Create API token

### 2. GitHub Actions

Add same tokens as repository secrets in Settings → Secrets.

### 3. Provider Credentials

Run `mise run setup` again to create providers entry, then update entry with values.

## Secret Rotation

### Automatic
- Tailscale keys: Renewed 30 days before expiry

### Manual
```bash
# Regenerate age keypair and re-encrypt all service secrets
tofu apply -replace='data.external.age_homelab["server-name"]'

# Regenerate Cloudflare tunnel
tofu apply -replace='cloudflare_zero_trust_tunnel_cloudflared.homelab["server-name"]'

# Rotate Tailscale key
tofu apply -target='tailscale_tailnet_key.homelab["server-name"]'
```

## SOPS/age Integration

### Server Setup (One-time)
Each Komodo server needs the age private key as an environment variable:

```bash
# Get age private key from 1Password
AGE_KEY=$(op item get "server-name" --vault="Homelab" --fields="age_private_key")

# Set environment variable for Komodo
export AGE_SECRET_KEY="$AGE_KEY"
```

### Local Development
To decrypt SOPS files locally for debugging:

```bash
# Export age key from 1Password
export AGE_SECRET_KEY=$(op item get "server-name" --vault="Homelab" --fields="age_private_key")

# Decrypt docker-compose file
sops -d docker/grafana/docker-compose.yaml
```

## Troubleshooting

```bash
# Check tokens
echo $OP_SERVICE_ACCOUNT_TOKEN
echo $AGE_SECRET_KEY

# Test 1Password
op vault list

# Verify provider credentials
op item get providers --vault="Homelab"

# Test SOPS decryption
sops -d --extract '["services"]["grafana"]["environment"]["GF_SECURITY_ADMIN_PASSWORD"]' docker/grafana/docker-compose.yaml
```
