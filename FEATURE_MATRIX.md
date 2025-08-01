# Feature Matrix

Complete configuration reference for all infrastructure and service options.

## Server Configuration

### Server Entry Structure (1Password)
```yaml
Name: server-REGION-NAME
Type: Login
Tags: server, PLATFORM, TYPE

Sections:
  inputs:
    description: "Server description"
    parent: "parent-region"
    region: "deployment-region"
    platform: "ubuntu|debian|alpine|truenas|haos|pbs|mac|proxmox|pikvm"
    type: "oci|proxmox|physical|vps"
    features:
      beszel: true|false      # System metrics
      cloudflare_proxy: true|false
      docker: true|false
      homepage: true|false
      
  # Platform-specific fields
  oci:
    boot_disk_size: "128"
    cpus: "4"
    memory: "8"
    shape: "VM.Standard.A1.Flex"
    
  proxmox:
    boot_disk_size: "128"
    cpus: "4" 
    memory: "8192"
    node: "proxmox-node-name"
    
  outputs:
    public_ip: "x.x.x.x"
    tailscale_ip: "100.x.x.x"
```

### Server Types

| Type | Description | Platform Support |
|------|-------------|------------------|
| `oci` | Oracle Cloud Infrastructure | ubuntu, debian |
| `proxmox` | Proxmox Virtual Environment | ubuntu, debian, alpine, truenas, haos, pbs |
| `physical` | Physical hardware | Any |
| `vps` | Virtual Private Server | ubuntu, debian, alpine |

### Server Platforms

| Platform | Description | Features |
|----------|-------------|----------|
| `ubuntu` | Ubuntu Server | docker, komodo, homepage |
| `debian` | Debian Server | docker, komodo |
| `alpine` | Alpine Linux | docker (lightweight) |
| `truenas` | TrueNAS Scale | storage, apps |
| `haos` | Home Assistant OS | home automation |
| `pbs` | Proxmox Backup Server | backup |
| `mac` | macOS | development |
| `proxmox` | Proxmox VE Host | virtualization |
| `pikvm` | PiKVM | remote management |

### Server Features

| Feature | Description | Requirements |
|---------|-------------|--------------|
| `beszel` | Beszel monitoring agent | System metrics |
| `cloudflare_proxy` | Use Cloudflare proxy | External DNS |
| `docker` | Docker runtime | ubuntu, debian, alpine |
| `homepage` | Homepage dashboard | docker |

## Service Configuration

### Service Entry Structure (1Password)
```yaml
Name: PLATFORM-SERVICE
Type: Login
Tags: PLATFORM, service

Sections:
  inputs:
    deployment: "all|none|tag:TAG|server:NAME|region:REGION"
    description: "Service description"
    dns:
      external: true|false
      internal: true|false
    
    # Platform-specific configuration
    docker:
      image: "image:tag"
      ports:
        - "8080:80"
        - "8443:443"
      volumes:
        - "data:/data"
      environment:
        KEY: "value"
        
    fly:
      regions:
        - "syd"
        - "sin"
      size: "shared-cpu-1x"
      
    vercel:
      framework: "nextjs|react|vue"
      
    features:
      auth_password: true|false
      database: "postgres|mysql"
      mail: "resend"
      storage_cloud: "b2"
      
  outputs:
    url: "https://service.example.com"
    admin_password: "generated"
```

### Deployment Targets

| Target | Description | Example |
|--------|-------------|---------|
| `all` | Deploy to all compatible servers | Default |
| `none` | No automatic deployment | Manual only |
| `tag:TAG` | Deploy to servers with tag | `tag:docker` |
| `server:NAME` | Deploy to specific server | `server:au-hsp` |
| `region:REGION` | Deploy to region | `region:au` |

### Service Platforms

| Platform | Description | Deployment |
|----------|-------------|------------|
| `docker` | Docker containers | Self-hosted |
| `fly` | Fly.io applications | Cloud |
| `vercel` | Vercel deployments | Cloud |

### Service Features

| Feature | Description | Configuration |
|---------|-------------|---------------|
| `auth_basic` | HTTP Basic Auth | Auto-generated |
| `auth_oauth` | OAuth2/OIDC | Provider config |
| `auth_password` | Password auth | Generated/custom |
| `auth_tailscale` | Tailscale ACL | Network-based |
| `backup` | Automated backups | B2 storage |
| `database` | Database backend | postgres, mysql |
| `mail` | Email sending | resend, smtp |
| `storage_cloud` | Cloud storage | b2, s3 |
| `storage_local` | Local volumes | Docker volumes |

## DNS Configuration

DNS is managed via `infrastructure/dns.auto.tfvars`:

```hcl
dns_zones = {
  "example.com" = {
    enabled = true
    proxied_default = true
    records = [
      {
        name     = "@"
        type     = "MX"
        content  = "mail.example.com"
        priority = 10
      },
      {
        name    = "_dmarc"
        type    = "TXT"
        content = "v=DMARC1; p=none;"
      }
    ]
  }
}
```

### Auto-Generated DNS

- Server external: `server.region.external-domain.com`
- Server internal: `server.region.internal-domain.dev`
- Service external: From Website field if enabled
- Service internal: From Website field if enabled

## Monitoring & Dashboard Configuration (Auto-Generated)

### Gatus Health Checks
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
      widget      = service.widget != null ? service.widget : null
    }
    if service.inputs.homepage != false
  }
}
```

### Homepage Examples

```yaml
# Docker service widget
widget:
  type: container
  server: "localhost"
  container: "service-name"

# Proxmox widget  
widget:
  type: proxmox
  url: "https://proxmox.example.com:8006"
  username: "viewer@pve"
  password: "readonly-token"
```

## Template Hierarchy

### Server Templates
```
router-REGION
└── server-REGION-NAME
    └── services (via deployment targeting)
```

### Service Templates
```
PLATFORM-SERVICE
├── docker-compose.yaml (generated)
├── caddy config (if needed)
└── homepage widget (if enabled)
```

## Common Patterns

### Multi-Server Service
```yaml
deployment: "tag:docker"  # Deploy to all Docker servers
```

### Region-Specific Service
```yaml
deployment: "region:au"  # Deploy only to AU region
```

### Single Server Service
```yaml
deployment: "server:au-hsp"  # Deploy to specific server
```

### External-Only Service
```yaml
deployment: "none"  # Fly.io, Vercel, manual
dns:
  external: true
  internal: false
```

## Configuration Files

### Infrastructure
- `infrastructure/terraform.auto.tfvars` - Main configuration
- `infrastructure/dns.auto.tfvars` - DNS zones and records

### Services  
- `services/terraform.auto.tfvars` - Service defaults

### Templates
- `templates/cloud_config/` - Server initialization
- `templates/docker/` - Docker compose templates
- `templates/gatus/` - Health check configuration
- `templates/homepage/` - Dashboard configuration
- `templates/ssh/` - SSH client config

## Deployment Workflow

### Service Deployment
Services are deployed based on their platform (Docker, Fly.io, Vercel) and deployment target configuration.

### Rollback Strategy
- Docker: Komodo handles container rollback
- Fly.io: Platform handles deployment rollback
- Configuration: Git revert and redeploy

## Security Patterns

### Network Security
- All internal traffic over Tailscale
- External access through Cloudflare proxy
- Service-to-service via Tailscale DNS

### Secret Management
- All secrets in 1Password
- Service accounts with minimal scope
- Automatic password generation

### Access Control
- Tailscale ACLs for network access
- Service-specific authentication
- No shared credentials

## Backup Strategy

### Automated Backups
```yaml
features:
  backup: true
  storage_cloud: "b2"
```

Configures:
- Daily snapshots to B2
- 30-day retention
- Automated restore testing

### Manual Backups
- Database dumps via scripts
- File backups via restic
- Configuration in Git

## Migration Patterns

### From Legacy Infrastructure
1. Create server entries in 1Password
2. Import existing services
3. Update DNS records
4. Migrate data

### Between Servers
1. Update deployment target
2. Run apply
3. Migrate persistent data
4. Update DNS

## Troubleshooting

### Common Issues
- Authentication failures: Check 1Password service account
- DNS not resolving: Verify zone configuration
- Service unreachable: Check Tailscale connection

### Debug Mode
```bash
export TF_LOG=DEBUG
mise run plan
```

## GitHub Actions

### Manual Workflow
The project uses manual GitHub Actions for safety:
- Restricted to repository owner
- Requires explicit confirmation
- Plans saved as artifacts

### Required Secrets
Only three secrets needed:
- `OP_SERVICE_ACCOUNT_TOKEN`
- `AWS_ACCESS_KEY_ID` (B2)
- `AWS_SECRET_ACCESS_KEY` (B2)