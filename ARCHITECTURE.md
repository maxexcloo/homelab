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
  komodo.tf     - Container deployment configs
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

## Container Deployment (Komodo)

### SOPS/age Encrypted Configuration Generation

The `komodo.tf` module renders actual `docker-compose.yaml` templates with real secret values, encrypts them using SOPS/age, and generates Komodo Stack configurations for deployment.

### Architecture Flow

1. **Service Discovery**: Scans 1Password vault for Docker services
2. **Age Key Generation**: Creates unique age keypairs per server, stored in 1Password
3. **Template Rendering**: Processes actual docker-compose.yaml files with real secret values
4. **SOPS Encryption**: Encrypts each docker-compose file with target server's age public key
5. **Repository Storage**: Commits SOPS-encrypted files to GitHub repository
6. **Komodo Deployment**: Stack pre-deploy hook decrypts secrets using server's age private key

### Template Variables

Each docker-compose template receives these variables before SOPS encryption:

**Default Variables** (available to all services):
- `default.email` - Organization email from `var.default_email`
- `default.organisation` - Organization name from `var.default_organization`
- `default.timezone` - Default timezone (Australia/Sydney)
- `default.locale` - System locale (en_US.UTF-8)
- `default.puid` / `default.pgid` - LinuxServer container user/group IDs
- `default.postgres_version` / `default.mariadb_version` - Database versions
- `default.oidc_title` - OIDC provider name ("Pocket ID")
- `default.oidc_url` - OIDC provider URL (from pocket-id service)

**Service Variables**:
- `service.fqdn` - Service FQDN (external or internal)
- `service.title` - Human-readable service name
- `service.url` - Full HTTPS URL to service
- `service.username` - Username from 1Password
- `service.zone` - "external" or "internal" routing
- `service.database_password` - **Real password** from 1Password (encrypted by SOPS)
- `service.oidc_client_id` / `service.oidc_client_secret` - **Real OIDC credentials** (encrypted by SOPS)
- `service.resend_api_key` - **Real API key** from server resources (encrypted by SOPS)

**Server Variables**:
- `server.name_upper` - Server name in UPPERCASE for resource references
- `server.timezone` - Server timezone with fallback to default
- `server.puid` / `server.pgid` - Server-specific user/group IDs
- `server.locale` / `server.language` - Localization settings
- `server.postgres_version` / `server.mariadb_version` - Database versions

### Secret Management (SOPS/age Encryption)

**Age Key Management**:
- Each server gets a unique age keypair generated by OpenTofu
- Private keys stored in 1Password homelab entries as `age_private_key`
- Public keys used by SOPS for server-specific encryption

**Secret Sources**:
- **Service-specific**: Database passwords, OIDC credentials, API keys from 1Password service entries
- **Server-inherited**: B2 storage, Resend API keys, Tailscale keys from homelab server resources

### Generated Files

**In Komodo Repository**:
- `docker/{service}/docker-compose.yaml` - **SOPS-encrypted** with real secret values
- `stacks.toml` - Komodo Stack configurations with SOPS pre-deploy hooks
- `servers.toml` - Server configurations
- `variables.toml` - Global configuration variables
- `ENCRYPTION.md` - Complete SOPS/age documentation and usage guide

### Deployment Flow

1. **OpenTofu Apply**: 
   - Generates age keypairs per server
   - Renders docker-compose templates with real secret values
   - SOPS encrypts each file using target server's age public key
   - Commits encrypted docker-compose files to GitHub

2. **Komodo Stack Deployment**:
   - Pulls SOPS-encrypted docker-compose files from repository
   - Pre-deploy hook: `sops -d -i docker-compose.yaml` (decrypts using server's age private key)
   - Runs `docker-compose up` with decrypted secrets

3. **Server Setup** (one-time):
   - Add server to Komodo via UI or GitOps
   - Set `AGE_SECRET_KEY` environment variable from 1Password `age_private_key` field

### Security Benefits

- **Encrypted at rest**: All secrets encrypted in git repository using age
- **Server isolation**: Each server can only decrypt secrets for services deployed to it
- **No external dependencies**: No secret management service required
- **Audit trail**: Git history tracks all encrypted secret changes
- **Key rotation**: Update age keys in 1Password to rotate encryption

## Security Model

- **Rotation**: Tailscale keys auto-renewed
- **Secrets**: 1Password service accounts
- **State**: HCP Terraform encrypted backend
- **Zero-trust**: Tailscale or Cloudflare Tunnels only
