# Architecture

## System Design

OpenTofu reads 1Password entries and provisions infrastructure resources automatically.

```
1Password → OpenTofu → Providers → Resources
    ↑          ↓
    └── Sync ←─┘
```

## Data Flow

1. **Discovery**: Read entries from 1Password vaults
2. **Processing**: Generate resource configurations  
3. **Provisioning**: Create resources via providers
4. **Sync**: Write credentials back to 1Password

## Module Structure

```
homelab_*.tf:
  discovery → processing → sync
  
services_*.tf:
  discovery → processing → sync

Supporting:
  b2.tf         - Backup buckets
  cloudflare.tf - DNS and tunnels
  locals_dns.tf - DNS record generation
  resend.tf     - Email services
  tailscale.tf  - Zero-trust networking
```

## Field Reference

### Server Input Fields

| Field | Description | Example |
|-------|-------------|---------|
| `description` | Human-readable description | Any text |
| `flags` | Resources to create (comma-separated) | `b2,cloudflare,resend,tailscale` |
| `management_port` | SSH/management port | `22` |
| `parent` | Parent router region (optional) | `au` |
| `paths` | Backup paths (comma-separated) | `/data,/config` |
| `platform` | Operating system | `ubuntu`, `truenas`, `proxmox`, etc. |
| `private_ipv4` | LAN IP address | `10.0.0.1` |
| `public_address` | Public hostname or IP | `server.example.com` or `1.2.3.4` |
| `public_ipv4` | Public IPv4 (optional) | `1.2.3.4` |
| `public_ipv6` | Public IPv6 (optional) | `2001:db8::1` |

### Server Output Fields (Auto-Generated)

| Field | Description |
|-------|-------------|
| `b2_application_key` | Bucket-specific API key |
| `b2_application_key_id` | Bucket-specific key ID |
| `b2_bucket_name` | Unique bucket name |
| `b2_endpoint` | S3-compatible endpoint |
| `cloudflare_account_token` | Scoped API token |
| `cloudflare_tunnel_token` | Tunnel credential |
| `fqdn_external` | External DNS name |
| `fqdn_internal` | Internal DNS name |
| `public_address` | Resolved public address |
| `region` | Extracted region code |
| `resend_api_key` | Email API key |
| `tailscale_auth_key` | Device auth key (90-day) |
| `tailscale_ipv4` | Assigned Tailscale IPv4 |
| `tailscale_ipv6` | Assigned Tailscale IPv6 |

### Service Input Fields

| Field | Description |
|-------|-------------|
| `deploy_to` | Deployment target |
| `description` | Service description |
| `docker.compose` | Full docker-compose.yaml content |
| `fly.*` | Fly.io configuration |

### Deployment Targets

- `all` - Deploy to all compatible servers
- `none` - No automatic deployment
- `platform:NAME` - Servers with specific platform
- `region:NAME` - Servers in specific region
- `server:NAME` - Specific server only

## Resource Flags

| Flag | Creates |
|------|---------|
| `b2` | Bucket + application key |
| `cloudflare` | Tunnel + API token |
| `resend` | Email API key |
| `tailscale` | Auth key + device |

## DNS Management

### Automatic Records

- **ACME**: `_acme-challenge.*.DOMAIN`
- **Servers**: `NAME.REGION.INTERNAL_DOMAIN`
- **Services**: `SERVICE.EXTERNAL_DOMAIN`

### Manual Records (dns.auto.tfvars)

```hcl
dns = {
  "domain.com" = [
    { name = "@", type = "A", content = "1.2.3.4", proxied = true },
    { name = "@", type = "MX", content = "mail.server", priority = 10 }
  ]
}
```

## Generated Templates

```
templates/
├── cloud_config/    # Server bootstrap
├── docker/          # Service compose files
├── gatus/           # Health checks
├── homepage/        # Dashboard
├── ssh/             # SSH config
└── www/             # Finger protocol
```

## Important Notes

### Naming Conventions
- **Routers**: `router-REGION` (e.g., `router-au`)
- **Servers**: `server-REGION-NAME` (e.g., `server-au-web`)
- **Services**: `PLATFORM-SERVICE` (e.g., `docker-grafana`)

### Parent Relationships
- Servers can have a parent router via the `parent` field
- Parent must exist before child can be created
- Used for network topology and inheritance

### Resource Creation
- Only creates resources specified in `flags` field
- Reduces costs and complexity
- Add/remove flags to control resources

### Secret Rotation
- Tailscale keys auto-renew 30 days before expiry
- Other secrets can be manually rotated
- Credentials stored in 1Password outputs

### Workflow
1. Create 1Password entry with just name/title
2. Run `tofu apply` to create input/output sections
3. Fill in input fields in 1Password
4. Run `tofu apply` again to provision resources

## Security Model

- **Rotation**: Tailscale keys auto-renewed
- **Secrets**: 1Password service accounts
- **State**: HCP Terraform encrypted backend
- **Zero-trust**: Tailscale or Cloudflare Tunnels only
