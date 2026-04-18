# Homelab

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.10+-blue)](https://opentofu.org/)
[![Status](https://img.shields.io/badge/status-active-success)](https://github.com/maxexcloo/homelab)

Infrastructure as code for homelab management using OpenTofu.

## Quick Start

```bash
# Clone repository
git clone https://github.com/maxexcloo/homelab.git
cd homelab

# Setup
mise run setup  # Creates .mise.local.toml template
mise run init   # Initialize OpenTofu

# Deploy
mise run plan   # Review changes
mise run apply  # Apply changes
```

## Prerequisites

- [mise](https://mise.jdx.dev/) for task management and tool installation
- Bitwarden account with **Servers** and **Services** collections created
- Terraform Cloud account for state backend

Run `mise run setup` to create `.mise.local.toml` from the template, then fill in credentials — see `.mise.local.toml.default` for the full list.

## Architecture

YAML files in `data/` are the source of truth. OpenTofu reads them, computes derived values, and provisions resources across the integrated providers.

```
data/
├── defaults.yml        # Global defaults and base schemas
├── dns/*.yml           # DNS zones and manual records
├── servers/*.yml       # Server definitions
└── services/*.yml      # Service deployments
    │
    ▼
OpenTofu
    ├── Bitwarden       Credential storage (one entry per server/service)
    ├── B2              Object storage buckets and keys
    ├── Cloudflare      DNS records, Zero Trust tunnels, ACME tokens
    ├── GitHub          SSH public keys; pushes Fly/Komodo/TrueNAS configs
    ├── Incus           Containers and VMs on managed hosts
    ├── OCI             Oracle Cloud VMs and networking
    ├── Resend          Email API keys
    └── Tailscale       VPN auth keys, ACLs, and device lookups
```

Rendered service configs (Docker Compose, Fly.toml, TrueNAS overrides) are SOPS-encrypted and pushed to the platform-specific GitHub repos listed in `data/defaults.yml`, where deployment runners consume them.

## Workflow

### Adding Servers

1. Create `data/servers/<key>.yml` following `schemas/server.json`
2. Fill in `platform`, `type`, `features`, `identity`, `networking`
3. Run `mise run plan` to review, `mise run apply` to provision

### Adding Services

1. Create `data/services/<key>.yml` following `schemas/service.json`
2. Fill in `deploy_to`, `features`, `identity`, `networking`
3. Optionally add a Docker Compose template at `services/<identity.service>/docker-compose.yaml`
4. Run `mise run plan` to review, `mise run apply` to provision

## Commands

```bash
mise run apply     # Apply infrastructure changes
mise run check     # Format check, validate, and lint
mise run fmt       # Format HCL and YAML data files
mise run init      # Initialize OpenTofu providers and backend
mise run lint      # Validate YAML data files against JSON schemas
mise run plan      # Review infrastructure changes
mise run refresh   # Check for configuration drift
mise run setup     # Initial project setup
mise run validate  # Validate OpenTofu configuration
```

## Credential Storage

All generated credentials are stored automatically in **Bitwarden** in two collections:

- **Servers** — one login entry per server; all generated fields (passwords, API keys, IPs, FQDNs, tunnel tokens) stored as custom fields
- **Services** — one login entry per service deployment with the same pattern

## Documentation

- [AGENTS.md](AGENTS.md) - Development guide and standards

## License

AGPL-3.0 - see [LICENSE](LICENSE)
