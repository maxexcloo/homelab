# 1Password Templates Guide

This guide explains how to manually create servers and services in 1Password using the provided templates.

## Server Template

The `template-server` entry in the Infrastructure vault contains all possible fields for a server.

### To create a new server manually:

1. **Duplicate the template**
   - Find `template-server` in Infrastructure vault
   - Click "..." → "Duplicate"
   - Rename to `server-REGION-NAME` (e.g., `server-au-web`)

2. **Update required fields**
   - **Title**: `server-REGION-NAME`
   - **URL**: `name.region.excloo.dev`
   - **Username**: Server username (usually `root`)
   - **Password**: Generate or set a secure password
   - **Tags**: Remove `template`, add `server` and platform/type tags

3. **Update sections**

#### inputs Section (Required)
```yaml
inputs:
  description: "Your server description"
  parent: "parent-region"  # e.g., "au" 
  region: "server-region"  # e.g., "au"
  platform: "ubuntu"       # ubuntu|debian|alpine|truenas|haos|pbs|mac|proxmox|pikvm
  type: "oci"             # oci|proxmox|physical|vps
  
  features:              # Set to true/false as needed
    beszel: true         # System monitoring
    cloudflare_proxy: true
    docker: true
    homepage: true
```

#### Platform-Specific Sections (Use relevant one)

**OCI Section** (Oracle Cloud):
```yaml
oci:
  boot_disk_size: "128"      # GB
  cpus: "4"                  # OCPUs
  memory: "8"                # GB
  shape: "VM.Standard.A1.Flex"
  compartment_id: "ocid1.compartment..."
  availability_domain: "AD-1"
```

**Proxmox Section**:
```yaml
proxmox:
  boot_disk_size: "128"      # GB
  cpus: "4"
  memory: "8192"             # MB
  node: "proxmox-node-name"
  vmid: "auto"               # or specific number
  template: "ubuntu-22.04"   # template name
```

#### outputs Section (Auto-populated)
```yaml
outputs:
  public_ip: ""              # Set by OpenTofu
  tailscale_ip: ""           # Set by OpenTofu
  ssh_host_key: ""           # Set by OpenTofu
```

## Service Template

The `template-service` entry in the Services vault contains all possible fields for a service.

### To create a new service manually:

1. **Duplicate the template**
   - Find `template-service` in Services vault
   - Click "..." → "Duplicate"
   - Rename to `PLATFORM-SERVICE` (e.g., `docker-grafana`)

2. **Update required fields**
   - **Title**: `PLATFORM-SERVICE`
   - **Username**: Service admin username
   - **Password**: Generate or set a secure password
   - **Tags**: Remove `template`, add platform tag and `service`

3. **Update sections**

#### inputs Section (Required)
```yaml
inputs:
  deployment: "all"          # all|none|tag:X|server:X|region:X
  description: "Service description"
  
  dns:
    external: true           # Public access
    internal: true           # Internal access
    redirects:              # Optional redirect domains
      - "old-domain.com"
      - "legacy.example.com"
```

#### Platform-Specific Configuration

**Docker Section**:
```yaml
docker:
  image: "grafana/grafana:latest"
  ports:
    - "3000:3000"
    - "3001:3001"
  volumes:
    - "data:/var/lib/grafana"
    - "config:/etc/grafana"
  environment:
    GF_SECURITY_ADMIN_PASSWORD: "changeme"
    GF_INSTALL_PLUGINS: "plugin1,plugin2"
  networks:
    - "proxy"
  command: ""                # Optional override
  restart: "unless-stopped"
```

**Fly.io Section**:
```yaml
fly:
  regions:
    - "syd"
    - "sin"
  size: "shared-cpu-1x"      # Instance size
  min_instances: 1
  max_instances: 3
  auto_stop: true
  auto_start: true
```

**Vercel Section**:
```yaml
vercel:
  framework: "nextjs"        # nextjs|react|vue|svelte
  build_command: "npm run build"
  output_directory: ".next"
  install_command: "npm install"
  dev_command: "npm run dev"
```

#### features Section
```yaml
features:
  auth_basic: false          # HTTP Basic Auth
  auth_oauth: false          # OAuth2/OIDC
  auth_password: true        # Password auth
  auth_tailscale: false      # Tailscale ACL only
  backup: true               # Automated backups
  database: "postgres"       # postgres|mysql|none
  mail: "resend"            # resend|smtp|none
  monitoring: true           # Include in monitoring
  storage_cloud: "b2"        # b2|s3|none
  storage_local: true        # Local volumes
```

#### outputs Section (Auto-populated)
```yaml
outputs:
  url: ""                    # Set by OpenTofu
  admin_password: ""         # Set by OpenTofu
  api_key: ""               # Set by OpenTofu
  webhook_url: ""           # Set by OpenTofu
```

## Providers Entry

The `providers` entry contains all API keys and configuration for external services.

### Provider Sections

```yaml
b2:
  application_key: "K002..."
  application_key_id: "002..."

cloudflare:
  account_id: "abc123..."
  api_token: "v1.0-e72..."

github:
  token: "ghp_..."
  username: "your-username"

oci:
  fingerprint: "aa:bb:cc..."
  private_key: "-----BEGIN PRIVATE KEY-----..."
  region: "ap-sydney-1"
  tenancy_ocid: "ocid1.tenancy..."
  user_ocid: "ocid1.user..."

onepassword:
  service_account_token: "ops_..."

proxmox:
  api_token: "PVEAPIToken=..."
  endpoint: "https://proxmox.example.com:8006"
  username: "root@pam"

resend:
  api_key: "re_..."

sftpgo:
  host: "sftpgo.example.com"
  password: "admin-password"
  username: "admin"

tailscale:
  api_key: "tskey-api-..."
  tailnet: "example.com"

fly:
  api_token: "fly_..."

vercel:
  api_token: "vercel_..."
  team_id: "team_..."
```

## Field Reference

### Required vs Optional

- **Required**: Fields needed for basic functionality
- **Optional**: Fields that enhance or customize behavior
- **Conditional**: Required only for specific platforms/features

### Field Types

- `text`: Plain text values
- `concealed`: Sensitive values (passwords, tokens)
- `url`: Website URLs
- Arrays: Use numbered keys (0, 1, 2...)
- Objects: Use dot notation

## Tips

1. **Start minimal**: Only fill in required fields first
2. **Use templates as reference**: Keep templates to see all available options
3. **Remove unused sections**: Delete sections you don't need
4. **Test incrementally**: Add features one at a time
5. **Keep passwords**: Generated passwords are your access credentials

## Common Patterns

### Development Service
```yaml
deployment: "server:dev-box"     # Single server
dns:
  external: false                # Internal only
  internal: true
features:
  auth_tailscale: true          # Network auth only
```

### Production Service
```yaml
deployment: "tag:production"     # All prod servers
dns:
  external: true                # Public access
  internal: true
features:
  auth_password: true           # Strong auth
  backup: true                  # Automated backups
  monitoring: true              # Health checks
```

### Multi-Region Service
```yaml
deployment: "all"               # All servers
docker:
  image: "app:latest"
  environment:
    REGION: "${server.region}"  # Region-aware
```

## Validation

Before using an entry:
1. Ensure required fields are filled
2. Remove any CHANGEME/REPLACE_ME values
3. Verify platform-specific sections match server type
4. Test with `mise run plan` before applying