# Feature Matrix

## Infrastructure Features

### Server Types
| Type | Provider | Configuration Fields | Notes |
|------|----------|---------------------|-------|
| `oci` | Oracle Cloud | `boot_disk_image_id`, `boot_disk_size`, `cpus`, `ingress_ports`, `memory`, `shape` | Free tier ARM instances |
| `proxmox` | Proxmox VE | `boot_disk_size`, `cpus`, `memory`, `node`, `template`, `vmid` | On-premise virtualization |
| `physical` | None | Manual configuration only | Existing hardware |
| `vps` | Various | Provider-specific | Digital Ocean, Linode, etc. |
| `router` | None | Gateway configuration | Network edge devices |

### Server Features
| Feature | Description | Purpose |
|---------|-------------|----------|
| `beszel` | Beszel monitoring agent | System monitoring |
| `cloudflare_proxy` | Enable Cloudflare tunnel | External access |
| `docker` | Docker host | Container runtime |
| `github_runner` | GitHub Actions runner | CI/CD |
| `homepage` | Show on homepage | Dashboard visibility |
| `portainer` | Portainer endpoint | Container management |
| `unifi` | UniFi controller | Network management |

### Platform Types
| Platform | Description | Typical Features |
|----------|-------------|------------------|
| `ubuntu` | Ubuntu Linux | docker, homepage |
| `truenas` | TrueNAS Scale | docker, portainer, storage |
| `haos` | Home Assistant OS | homepage, automation |
| `pbs` | Proxmox Backup Server | backup, monitoring |
| `mac` | macOS | docker, development |
| `proxmox` | Proxmox VE | virtualization, homepage |
| `pikvm` | PiKVM | remote access |

### Infrastructure Services
| Service | Purpose | Configuration |
|---------|---------|---------------|
| Cloudflare | DNS zones, tunnels | API key, zones, tokens |
| Tailscale | Zero-trust networking | Auth keys, ACLs |
| B2 | State storage, backups | Application keys |
| SFTPGO | Local file storage | Users, folders |
| Resend | Email infrastructure | Domain verification |
| GitHub | Runners, deployments | Tokens, secrets |
| Proxmox | VM management | API credentials |

## Service Features

### Deployment Targets
| Format | Example | Description |
|--------|---------|-------------|
| `all` | `deployment: "all"` | Deploy to all servers |
| `none` | `deployment: "none"` | No deployment (config only) |
| `tag:*` | `deployment: "tag:docker"` | Deploy to servers with feature |
| `server:*` | `deployment: "server:au-hsp"` | Deploy to specific server |
| `region:*` | `deployment: "region:au"` | Deploy to servers in region |

### Service Features
| Feature | Description | Resources Created |
|---------|-------------|-------------------|
| `auth_password` | Use 1Password entry password | Password passed to service |
| `auth_secret_hash` | Generate bcrypt hash | Hash stored in outputs |
| `database` | Database requirement | Connection string, credentials |
| `mail` | Email sending capability | API keys, SMTP config |
| `observability` | Logs, metrics, traces | Collector configuration |
| `storage_cloud` | Cloud storage (B2) | Bucket, access keys |
| `storage_sftp` | SFTP storage | User, folder, credentials |

### Platform Support
| Platform | Entry Prefix | Deployment Method | Config Section |
|----------|--------------|-------------------|----------------|
| Docker | `docker-*` | Komodo API | `inputs.docker` |
| Fly.io | `fly-*` | Fly CLI/API | `inputs.fly` |
| Vercel | `vercel-*` | Vercel API | `inputs.vercel` |

## Service Naming Convention

### Format: `platform-service` (No Server Suffix)

| Platform | Example | Deployment |
|----------|---------|------------|
| `docker-*` | `docker-grafana` | Via deployment target |
| `fly-*` | `fly-app` | Multi-region native |
| `vercel-*` | `vercel-site` | Global CDN |

### Multi-Server Services
Services share the same 1Password entry with deployment targets:
- Single entry: `docker-caddy`
- Deployment: `tag:reverse_proxy` or `all`
- Shared credentials across all instances

## Service Configuration

### Docker Configuration
```yaml
inputs:
  deployment: "server:au-hsp"  # or "tag:docker" or "region:au"
  description: "Application Description"  # Pretty name for UI
  icon: "app-icon"  # Homepage icon
  docker:
    image: "app:latest"
    ports: ["3000:3000"]
    volumes: 
      - "data:/data"
    environment:
      KEY: "value"
    networks: ["internal"]
    depends_on: ["database"]
  widgets:  # Homepage widgets
    - widget:
        type: "customapi"
        url: "${url}/api/stats"
        mappings:
          - field: users
            label: "Users"
```

### Fly.io Configuration
```yaml
inputs:
  fly:
    app_name: "my-app"
    regions: ["syd", "lax"]
    size: "shared-cpu-1x"
    services:
      - internal_port: 3000
        protocol: "tcp"
        ports:
          - handlers: ["http"]
            port: 80
          - handlers: ["tls", "http"]
            port: 443
```

### DNS Configuration
Multiple websites in 1Password entry:
- `Website`: Primary External URL (e.g., `https://service.excloo.net`)
- `Website 2`: Internal URL (e.g., `https://service.excloo.dev`)
- `Website 3+`: Legacy URLs (redirect to primary)

**Auto-Generated DNS:**
- External: From Website field if `.net` domain
- Internal: From Website fields if `.dev` domain
- Server subdomain: `service.server.location.dev` auto-created
- Wildcards: `*.server.location.domain` for dynamic services

**DNS Zone Management:**
- Zones stored as `dns-domain-tld` entries in Infrastructure vault
- Manual records in zone entry `records` section
- Auto-sync from Cloudflare zones

## SSL Certificate Management

### Domain Structure
- **External Domain**: `.net` (e.g., `excloo.net`)
  - Resolves to public IPs or Cloudflare proxy
  - SSL via Cloudflare proxy or Caddy with Let's Encrypt
- **Internal Domain**: `.dev` (e.g., `excloo.dev`)
  - Resolves to Tailscale IPs (IPv4 and IPv6)
  - SSL via Caddy with Cloudflare DNS validation

### DNS Patterns
- **Server DNS**:
  - External: `server.excloo.net` → Public IP
  - Internal: `server.excloo.dev` → Tailscale IP
- **Service DNS**:
  - External: `service.excloo.net` → Cloudflare/Public
  - Internal: `service.server.excloo.dev` → Tailscale IP
  - Internal Alt: `service.excloo.dev` → Tailscale IP

### SSL Implementation
```hcl
# External - Cloudflare Proxy
resource "cloudflare_record" "external" {
  zone_id = data.cloudflare_zone.external.id
  name    = var.service_name
  type    = "CNAME"
  value   = "${var.server_name}.${var.external_domain}"
  proxied = true  # Cloudflare SSL
}

# External - Caddy (port forwarding)
resource "caddy_site" "external" {
  address = "${var.service_name}.${var.external_domain}"
  
  tls {
    # Let's Encrypt via HTTP challenge
  }
  
  reverse_proxy {
    to = "localhost:${var.service_port}"
  }
}

# Internal - Caddy with DNS validation
resource "caddy_site" "internal" {
  address = "${var.service_name}.${var.server_name}.${var.internal_domain}"
  
  tls {
    dns cloudflare {
      api_token = var.cloudflare_api_token
    }
  }
  
  reverse_proxy {
    to = "localhost:${var.service_port}"
  }
}
```

## Config Files in 1Password
```yaml
outputs:
  files:
    "gatus.yaml": |
      endpoints:
        - name: "Service Health"
          url: "https://service.excloo.dev/health"
          interval: 60s
          conditions:
            - "[STATUS] == 200"
    "homepage_services.yaml": |
      - Service:
          icon: service.png
          href: https://service.excloo.dev
          description: Service description
    "docker-compose.yml": |
      version: "3.8"
      services:
        app:
          image: app:latest
```

## Komodo Integration Options

### Option 1: Direct API Integration (Recommended)
- OpenTofu generates compose files from 1Password
- Deploys directly via Komodo API
- Handles updates and rollbacks

### Option 2: GitOps Integration
- OpenTofu commits compose files to git repo
- Komodo watches repo for changes
- Automatic deployment on commit

### Option 3: Hybrid Approach
- Critical configs in 1Password
- Compose files in git for version control
- Komodo syncs from both sources

## Service Dependencies

### Dependency Management
```yaml
inputs:
  depends_on:
    - "docker-postgres"  # Must be deployed first
    - "docker-redis"     # Must be deployed first
  
outputs:
  provides:
    - "auth_endpoint"    # For other services to consume
    - "api_base_url"     # For other services to consume
```

### Cross-Service Communication
```yaml
# Service A
outputs:
  provides:
    database_url: "postgres://..."

# Service B  
inputs:
  requires:
    database_url: "${service.docker-postgres.outputs.database_url}"
```

## Automatic Rollback Strategy

### Health Check Based Rollback
```hcl
# modules/service/rollback.tf
resource "null_resource" "health_check" {
  depends_on = [komodo_stack.service]
  
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for service to start
      sleep 30
      
      # Check health endpoint
      for i in {1..5}; do
        if curl -f https://${var.service_name}.${var.internal_domain}/health; then
          echo "Health check passed"
          exit 0
        fi
        sleep 10
      done
      
      # Rollback if health check fails
      echo "Health check failed, rolling back"
      curl -X POST ${var.komodo_api}/stacks/${self.triggers.stack_id}/rollback
    EOT
  }
  
  triggers = {
    stack_id = komodo_stack.service.id
    version  = komodo_stack.service.version
  }
}
```

### Rollback Triggers
- Failed health checks after deployment
- Container restart loops (>3 in 5 minutes)
- Memory/CPU threshold breaches (>90%)
- Missing required dependencies
- HTTP 5xx error rates >10%

## Backup Testing Service

### Automated Backup Verification
```yaml
# 1Password Entry: docker-backup-tester-au-hsp
inputs:
  deployment: "all"
  docker:
    image: "backup-tester:latest"
    environment:
      BACKUP_SOURCES: "b2://bucket/path,sftp://server/path"
      ALERT_EMAIL: "alerts@excloo.com"
      TEST_SCHEDULE: "0 0 * * 0"  # Weekly
      RESTORE_TEST_SIZE: "100MB"  # Max size to test
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "test-restore:/restore"  # Temporary restore location
```

## Server Configuration Details

### Server Inheritance

Servers can inherit configuration from parent routers/servers:

```yaml
# Router entry (parent)
Name: router-au
Sections:
  inputs:
    region: "au"
    features:
      homepage: true
    networks:
      - public_address: "au.dyndns.org"

# Server entry (child)
Name: server-au-hsp  
Sections:
  inputs:
    parent: "au"  # Inherits from router-au
    # Inherits: region, some features, network config
```

### User Configuration
```yaml
inputs:
  user:
    fullname: "Max Schaefer"
    username: "max.schaefer"  # Overrides default
    groups: ["docker", "sudo", "admin"]
    paths:  # Platform-specific paths
      - "/home/max.schaefer"  # Linux
      - "/Users/max.schaefer"  # macOS
      - "/Volumes"  # macOS external
    shell: "/bin/bash"
```

### Network Configuration
```yaml
inputs:
  networks:
    - public_ipv4: "1.2.3.4"
      public_ipv6: "2001:db8::1"
      public_address: "server.dyndns.org"  # For routers
    - vlan_id: 3  # Additional network
      firewall: true
```

### Server Services
```yaml
inputs:
  services:  # Services running on the server itself
    - service: "proxmox"
      port: 8006
      icon: "proxmox"
      title: "Proxmox VE"
      enable_ssl_validation: false
      widgets:
        - widget:
            type: "proxmox"
            url: "${url}"
            username: "${username}@pam"
            password: "${password}"
    - service: "truenas"
      port: 443
      icon: "truenas"
      title: "TrueNAS Scale"
```

## Monitoring & Alerting (Auto-Generated)

### Gatus Configuration
```hcl
# Automatically generated from service definitions
locals {
  gatus_config = {
    endpoints = [
      for name, service in local.services : {
        name = service.title != null ? service.title : title(replace(name, "-", " "))
        url  = "https://${name}.${var.internal_domain}/health"
        interval = "60s"
        conditions = [
          "[STATUS] == 200",
          "[RESPONSE_TIME] < 1000"
        ]
        alerts = [{
          type        = "email"
          enabled     = true
          description = "${name} is down"
          send_on_resolved = true
        }]
      }
      if service.inputs.monitoring != false
    ]
  }
}
```

### Homepage Configuration
```hcl
# Automatically generated from service definitions
locals {
  homepage_services = {
    for name, service in local.services : name => {
      name        = service.title != null ? service.title : title(replace(name, "-", " "))
      icon        = service.icon != null ? service.icon : "mdi-docker"
      href        = "https://${name}.${var.internal_domain}"
      description = service.description != null ? service.description : "${name} service"
      server      = service.inputs.deployment
      widget      = service.widget != null ? service.widget : null
    }
    if service.inputs.homepage != false
  }
}
```

## GitHub Actions Security

### Option 1: Environment Protection Rules
```yaml
jobs:
  deploy:
    environment: production  # Requires approval
    if: github.actor == 'maxexcloo'  # Only you
```

### Option 2: Repository Secrets + OIDC
```yaml
permissions:
  id-token: write
  contents: read
  
steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_ROLE }}
```

### Option 3: Private Actions in Public Repo (Recommended)
- Use workflow conditions: `if: github.actor == 'maxexcloo'`
- Store sensitive outputs as artifacts (private to repo)
- Use environment secrets for credentials
- Manual workflow dispatch only