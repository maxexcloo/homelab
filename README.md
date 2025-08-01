# Homelab

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-active-success)](https://github.com/maxexcloo/homelab)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.6+-blue)](https://opentofu.org/)

Unified homelab infrastructure and services management using OpenTofu with 1Password as the single source of truth.

## Quick Start

```bash
# Clone repository
git clone https://github.com/maxexcloo/homelab.git
cd homelab

# Initial setup
mise run setup

# Initialize OpenTofu
mise run init

# Plan changes
mise run plan

# Apply
mise run apply
```

## Features

- **1Password Integration**: All configuration and secrets in one place
- **Multi-Platform**: Docker, Fly.io, Cloudflare Workers, Vercel
- **Zero-Trust Networking**: Tailscale mesh with automatic DNS
- **Automated Monitoring**: Gatus health checks and Homepage dashboard
- **GitOps Ready**: GitHub Actions for automated deployments
- **State Management**: Encrypted state in Backblaze B2

## Prerequisites

- [1Password CLI](https://1password.com/downloads/command-line/) with service account
- [OpenTofu](https://opentofu.org/) 1.6+
- [mise](https://mise.jdx.dev/) for task management
- Provider accounts (Cloudflare, Tailscale, B2, etc.)

## Project Structure

```
homelab/
├── infrastructure/     # Servers and core infrastructure
├── services/          # Service deployments
├── modules/           # Reusable OpenTofu modules
├── templates/         # Configuration templates
├── .github/           # GitHub Actions workflows
└── .mise.toml        # Development tasks
```

## Configuration

### 1Password Setup

Create two vaults:
- **Infrastructure**: Servers, DNS zones, provider credentials
- **Services**: Application definitions and outputs

### Common Tasks

```bash
# Create a new server (via CLI)
mise run server au-web oci

# Create a new service (via CLI)
mise run service docker-grafana

# List all infrastructure
mise run list

# Clean up generated files
mise run clean
```

**Manual Creation**: You can also duplicate the `template-server` or `template-service` entries in 1Password. See [TEMPLATES.md](TEMPLATES.md) for details.

### DNS Configuration

Edit `infrastructure/dns.auto.tfvars` to manage DNS zones and manual records:

```hcl
dns_zones = {
  "example.com" = {
    enabled = true
    proxied_default = true
    records = [
      { name = "@", type = "MX", content = "mail.example.com", priority = 10 }
    ]
  }
}
```

## Development

```bash
# Format code
mise run fmt

# Validate configuration
mise run validate
```

## Documentation

- [Architecture](ARCHITECTURE.md) - System design and patterns
- [Feature Matrix](FEATURE_MATRIX.md) - Complete configuration reference
- [DNS Management](DNS_ARCHITECTURE.md) - DNS strategy and patterns
- [Templates Guide](TEMPLATES.md) - Manual creation in 1Password
- [Development Guide](CLAUDE.md) - Standards and guidelines

## License

This project is licensed under the AGPL-3.0 License - see the [LICENSE](LICENSE) file for details.
