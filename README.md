# Homelab

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.8+-blue)](https://opentofu.org/)
[![Status](https://img.shields.io/badge/status-active-success)](https://github.com/maxexcloo/homelab)

Infrastructure as code for homelab management using OpenTofu, Bitwarden, and Sveltia CMS.

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
- Bitwarden account with **Servers** and **Services** folders created
- Terraform Cloud account for state backend

Run `mise run setup` to create `.mise.local.toml` from the template, then fill in credentials — see `.mise.local.toml.default` for the full list.

## Architecture

Data flows from **Sveltia CMS** → **YAML files** in `data/` → **OpenTofu** → infrastructure providers.

```
Sveltia CMS (admin/)
    │
    ▼
data/
├── defaults.yml        # Global defaults and base schemas
├── dns/*.yml           # DNS zones and manual records
├── incus/              # Incus profiles and projects
├── servers/*.yml       # Server definitions
└── services/*.yml      # Service deployments
    │
    ▼
OpenTofu
    ├── Bitwarden       Credential storage (one entry per server/service)
    ├── B2              Object storage buckets and keys
    ├── Cloudflare      DNS records, Zero Trust tunnels, ACME tokens
    ├── GitHub          SSH public keys injected into server cloud-init
    ├── Incus           Profiles, projects, containers, and VMs
    ├── Komodo          SOPS-encrypted compose files + server/stack configs → GitHub repo
    ├── OCI             Oracle Cloud VMs and networking
    ├── Resend          Email API keys
    ├── Tailscale       VPN auth keys and device lookups
    └── Talos           Kubernetes cluster node locals (control-plane/worker)
```

## Workflow

### Adding Servers

1. Open **Sveltia CMS** → Servers → New
2. Fill in `id`, `platform`, `type`, `features`, `identity`, `networking`
3. Commit via Sveltia CMS
4. Run `mise run plan` to review, `mise run apply` to provision

### Adding Services

1. Open **Sveltia CMS** → Services → New
2. Fill in `id`, `deploy_to`, `features`, `identity`, `networking`
3. Commit via Sveltia CMS
4. Run `mise run plan` to review, `mise run apply` to provision

## Commands

```bash
mise run apply     # Apply infrastructure changes
mise run check     # Format and validate (fmt + validate)
mise run fmt       # Format HCL and YAML data files
mise run init      # Initialize OpenTofu providers and backend
mise run plan      # Review infrastructure changes
mise run refresh   # Check for configuration drift
mise run setup     # Initial project setup
mise run validate  # Validate OpenTofu configuration
```

## Credential Storage

All generated credentials are stored automatically in **Bitwarden** in two folders:

- **Servers** — one login entry per server; all generated fields (passwords, API keys, IPs, FQDNs, tunnel tokens) stored as custom fields
- **Services** — one login entry per service deployment with the same pattern

## Documentation

- [AGENTS.md](AGENTS.md) - Development guide and standards

## License

AGPL-3.0 - see [LICENSE](LICENSE)
