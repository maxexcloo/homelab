# 1Password Templates Guide

This guide explains how to manually create servers and services in 1Password using the provided templates.

## Server Template

The `template-server` entry in the Infrastructure vault contains all required fields for a server.

### To create a new server manually:

1. **Duplicate the template**
   - Find `template-server` in Infrastructure vault
   - Click "..." → "Duplicate"
   - Rename to `server-REGION-NAME` (e.g., `server-au-web`)

2. **Update the fields**
   - **Title**: `server-REGION-NAME`
   - **URL**: `name.region.excloo.dev`
   - **Tags**: Remove `template`, add appropriate tags (`server`, `oci`, `ubuntu`)
   - **Sections → inputs**:
     - `description`: Your server description
     - `parent`: Parent region (e.g., `au`)
     - `region`: Server region (e.g., `au`)
     - `platform`: OS platform (`ubuntu`, `debian`, `alpine`)
     - `type`: Server type (`oci`, `proxmox`, `physical`, `vps`)
   - **Sections → inputs → features** (set to `true` or `false`):
     - `beszel`: System monitoring
     - `cloudflare_proxy`: Use Cloudflare proxy
     - `docker`: Docker installed
     - `homepage`: Show on homepage
     - Additional features as needed

3. **Platform-specific fields** (add as needed):
   - **OCI**: `oci.boot_disk_size`, `oci.cpus`, `oci.memory`, `oci.shape`
   - **Proxmox**: `proxmox.boot_disk_size`, `proxmox.cpus`, `proxmox.memory`, `proxmox.node`

## Service Template

The `template-service` entry in the Services vault contains all required fields for a service.

### To create a new service manually:

1. **Duplicate the template**
   - Find `template-service` in Services vault
   - Click "..." → "Duplicate"
   - Rename to `PLATFORM-SERVICE` (e.g., `docker-grafana`)

2. **Update the fields**
   - **Title**: `PLATFORM-SERVICE`
   - **URL**: `service.excloo.net` (if external DNS enabled)
   - **Tags**: Remove `template`, add `PLATFORM`, `service`
   - **Sections → inputs**:
     - `deployment`: Deployment target (`all`, `none`, `tag:docker`, `server:au-hsp`)
     - `description`: Service description
   - **Sections → inputs → dns**:
     - `external`: `true` for public access
     - `internal`: `true` for internal access
   - **Platform-specific configuration**:
     - **Docker**: 
       - `docker.image`: Docker image name
       - `docker.ports.0`, `docker.ports.1`: Port mappings
       - `docker.volumes.0`: Volume mounts
       - `docker.environment.KEY`: Environment variables
     - **Fly.io**:
       - `fly.regions.0`: Deployment regions
       - `fly.size`: Instance size
     - **Vercel**:
       - `vercel.framework`: Framework type

3. **Common features** (in `inputs.features`):
   - `auth_password`: Password authentication
   - `database`: Database type (`postgres`, `mysql`)
   - `mail`: Mail provider (`resend`)
   - `storage_cloud`: Cloud storage (`b2`)

## Field Reference

### Server Fields
```yaml
inputs:
  description: "Server description"
  parent: "parent-region"
  region: "deployment-region"
  platform: "ubuntu|debian|alpine"
  type: "oci|proxmox|physical|vps"
  features:
    beszel: true
    cloudflare_proxy: true
    docker: true
    homepage: true
```

### Service Fields
```yaml
inputs:
  deployment: "all|none|tag:X|server:X"
  description: "Service description"
  dns:
    external: true
    internal: true
  docker:
    image: "image:tag"
    ports:
      - "8080:80"
    environment:
      KEY: "value"
  features:
    auth_password: true
    database: "postgres"
```

## Tips

1. **Use consistent naming**: 
   - Servers: `server-REGION-NAME`
   - Services: `PLATFORM-SERVICE`

2. **Tag appropriately**: Tags help with filtering and organization

3. **Keep passwords**: The generated passwords are used for server/service access

4. **Update templates**: If you find yourself adding the same fields repeatedly, update the template

5. **Verify before applying**: Always run `mise run plan` to verify changes

## Common Patterns

### Multi-server service
```yaml
deployment: "tag:docker"  # Deploy to all servers with docker tag
```

### Region-specific service
```yaml
deployment: "region:au"  # Deploy only to AU region
```

### Single server service
```yaml
deployment: "server:au-hsp"  # Deploy to specific server
```

### No deployment (manual/external)
```yaml
deployment: "none"  # Don't deploy automatically
```