# Homelab

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.8+-blue)](https://opentofu.org/)
[![Status](https://img.shields.io/badge/status-active-success)](https://github.com/maxexcloo/homelab)

Infrastructure as code for homelab management using OpenTofu and 1Password.

## Quick Start

```bash
# Clone repository
git clone https://github.com/maxexcloo/homelab.git
cd homelab

# Setup
mise run setup  # Creates providers entry in 1Password
mise run init   # Initialize OpenTofu

# Deploy
mise run plan   # Review changes
mise run apply  # Apply changes
```

## Prerequisites

- [1Password CLI](https://1password.com/downloads/command-line/) with service account
- [mise](https://mise.jdx.dev/) for task management
- [OpenTofu](https://opentofu.org/) 1.8+

Create `.mise.local.toml`:
```toml
[env]
OP_SERVICE_ACCOUNT_TOKEN = "ops_..."     # From 1Password
TF_TOKEN_app_terraform_io = "..."        # From HCP Terraform
```

## Workflow

### Adding Infrastructure

1. **Create entry** in 1Password Homelab vault (e.g., `server-au-web`)
2. **Run apply** - OpenTofu creates input/output sections
3. **Fill inputs** in 1Password (platform, flags, etc.)
4. **Run apply** again - Resources are provisioned

### Adding Services

1. **Create entry** in 1Password Services vault (e.g., `docker-grafana`)
2. **Run apply** - OpenTofu creates input/output sections
3. **Fill inputs** in 1Password (deploy_to, docker compose, etc.)
4. **Run apply** again - Templates are generated

## Configuration

### Variables (terraform.auto.tfvars)

```hcl
default_email        = "admin@example.com"
default_organization = "My Homelab"
domain_acme         = "acme.duckdns.org"
domain_external     = "example.com"
domain_internal     = "internal.example"
```

### DNS Records (dns.auto.tfvars)

```hcl
dns = {
  "example.com" = [
    { name = "@", type = "A", content = "1.2.3.4" },
    { name = "@", type = "MX", content = "mail.server", priority = 10 }
  ]
}
```

## 1Password Structure

### Homelab Vault

```yaml
providers:  # Required - run 'mise run setup' first
  b2, cloudflare, hcp, resend, tailscale sections

router-REGION:  # e.g., router-au
  inputs:  # Created on first apply, then fill these
  outputs: # Auto-generated credentials

server-REGION-NAME:  # e.g., server-au-web
  inputs:  # Created on first apply, then fill these
  outputs: # Auto-generated credentials
```

### Services Vault

```yaml
PLATFORM-SERVICE:  # e.g., docker-grafana
  username: admin
  password: (shared across deployments)
  inputs:  # Created on first apply, then fill these
  outputs: # Auto-generated URLs
```

## Commands

```bash
mise run apply     # Deploy changes
mise run check     # Format and validate
mise run clean     # Clean up
mise run plan      # Review changes
mise run refresh   # Check drift
```

## Documentation

- [AGENTS.md](AGENTS.md) - Development guide
- [ARCHITECTURE.md](ARCHITECTURE.md) - System design and field reference
- [SECRETS.md](SECRETS.md) - Secret setup

## License

AGPL-3.0 - see [LICENSE](LICENSE)
