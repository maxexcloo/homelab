# Secrets Setup

## Auto-Generated Secrets

These are created automatically per server:

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
