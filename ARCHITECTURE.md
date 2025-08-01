# Homelab Architecture (Final)

## Overview

Unified homelab infrastructure and services management using OpenTofu with 1Password as the single source of truth.

## Core Principles

- **KISS**: Keep It Simple, Stupid - prefer simple solutions
- **Single Source of Truth**: 1Password stores all configuration
- **Infrastructure as Code**: All resources managed via OpenTofu
- **No Lock-in**: Avoid vendor-specific features where possible

## 1Password Structure

```
Infrastructure/
├── dns-excloo-com      # DNS zones
├── dns-excloo-dev
├── dns-excloo-net
├── providers           # All provider credentials
├── router-au           # Routers by region
├── server-au-hsp       # Servers by region-name
├── server-au-pie
└── server-us-west

Services/
├── docker-grafana      # Services by platform-name
├── docker-homepage
├── fly-app
└── cf-worker
```

## Server Configuration

```yaml
Name: server-au-hsp
Username: root
Password: [generated]
URL: hsp.au.excloo.dev

Sections:
  inputs:
    description: "Sydney HSP Server"
    parent: "au"       # Parent router/server (inherits config)
    region: "au"       # Region for deployment targeting
    platform: "ubuntu"  # ubuntu|truenas|haos|pbs|mac|proxmox|pikvm
    type: "oci"         # oci|proxmox|physical|vps
    features:
      beszel: true          # Monitoring
      cloudflare_proxy: true  # CF tunnel
      docker: true          # Container host
      homepage: true        # Dashboard
    
  oci:  # Type-specific config
    boot_disk_image_id: "..."
    boot_disk_size: 128
    cpus: 4
    memory: 8
    
  outputs:
    cloudflare_tunnel_token: "..."
    tailscale_auth_key: "..."
    tailscale_ip: "100.64.0.1"
```

## Service Configuration

```yaml
Name: docker-grafana
Username: admin
Password: [shared across deployments]
Website: https://grafana.excloo.net      # External
Website 2: https://grafana.excloo.dev    # Internal
Website 3: https://metrics.excloo.com    # Redirect

Sections:
  inputs:
    deployment: "tag:docker"  # all|none|tag:X|server:X|region:X
    description: "Grafana Metrics"
    dns:
      external: true     # Auto-create external DNS
      internal: true     # Auto-create internal DNS
      redirects:         # Additional domains (301 redirect)
        - "metrics.excloo.com"
        - "monitoring.excloo.net"
    features:
      auth_password: true     # Use 1Password creds
      database: "postgres"
      mail: "resend"
      observability:          # Per-service observability
        logs: true
        metrics: true
        traces: true
      storage_cloud: "b2"
    config:  # Arbitrary env vars
      CUSTOM_KEY: "value"
    docker:
      image: "grafana/grafana:latest"
      ports: ["3000:3000"]
      
  outputs:
    database_url: "postgres://..."
    mail_api_key: "re_..."
    files:
      "gatus.yaml": |
        endpoints:
          - name: Grafana
            url: https://grafana.excloo.dev/health
```

## DNS Management

### Simplified DNS Configuration
```yaml
# Service inputs
dns:
  external: true      # Creates service.excloo.net
  internal: true      # Creates service.excloo.dev
  redirects:          # Creates redirects to primary
    - "old-name.excloo.com"
    - "legacy.excloo.net"
```

### DNS Zone Entries
```yaml
Name: dns-excloo-com

Sections:
  inputs:
    zone: "excloo.com"
    
  records:  # Manual DNS records only
    - name: "@"
      type: "MX"
      content: "mail.server.com"
      priority: 10
```

## Observability Options

### Simple Per-Service Config
```yaml
# In service inputs
observability:
  logs: true      # Ship to Loki
  metrics: true   # Prometheus metrics
  traces: true    # OpenTelemetry traces
```

### Auto-instrumentation
- Docker services get OTEL sidecar if enabled
- Fly apps get environment variables
- All use unified collector endpoint

## Security & Secrets

### Tailscale Integration
- Auth keys auto-renewed before expiry
- ACLs managed in code
- No vendor lock-in (can switch to WireGuard)

### SSL/TLS
- External: Cloudflare proxy OR Caddy
- Internal: Caddy with CF DNS validation
- Auto-generated for all services

## Pre-commit Hooks

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/opentofu/opentofu
    hooks:
      - id: tofu-fmt
      - id: tofu-validate
  - repo: local
    hooks:
      - id: check-sorting
        name: Check HCL sorting
        entry: scripts/check-sorting.sh
```

## Deployment Workflow

### Local (mise)
```bash
mise run init      # Initialize
mise run plan      # Review changes
mise run apply     # Deploy
```

### GitHub Actions
- Manual dispatch only
- Restricted to your user
- Plans as artifacts (hidden from public)

## State Management

- Backend: B2 (S3 compatible)
- Encryption: At rest in B2
- Locking: Via S3 API
- No local state files

## Migration Path

1. **Phase 1**: Infrastructure
   - Create 1Password structure
   - Define all servers
   - Set up networking

2. **Phase 2**: Services  
   - Migrate service definitions
   - Set up Komodo integration
   - Configure monitoring

3. **Phase 3**: Cleanup
   - Remove legacy resources
   - Archive old repos

## Key Decisions

1. **No Kubernetes**: Docker only for now
2. **No Service Mesh**: Tailscale for networking
3. **Simple Monitoring**: Gatus + Homepage
4. **Manual Secrets**: Rotate in 1Password UI
5. **Direct API**: Komodo API, not GitOps

## Benefits

- **Simple**: One entry per service, clear patterns
- **Flexible**: Multi-platform, multi-region
- **Secure**: Zero-trust networking, encrypted state
- **Observable**: Optional logs/metrics/traces
- **Maintainable**: Clear separation of concerns