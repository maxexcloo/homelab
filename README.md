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

### GitHub Actions

Simple CI/CD workflow:

- **Pull Requests**: Runs `mise run check` (format + validate)
- **Push to main**: Runs `mise run plan`
- **Daily schedule**: Runs `mise run refresh` (drift detection)
- **Manual dispatch**: Choose action (`plan`/`apply`) and target (`both`/`infrastructure`/`services`)

## Features

- **1Password Integration**: All configuration and secrets in one place
- **Automated Monitoring**: Gatus health checks and Homepage dashboard
- **GitOps Ready**: GitHub Actions for automated deployments
- **Multi-Platform**: Docker, Fly.io, Cloudflare Workers, Vercel
- **State Management**: Secure remote state in HCP Terraform
- **Zero-Trust Networking**: Tailscale mesh with automatic DNS

## Prerequisites

- [1Password CLI](https://1password.com/downloads/command-line/) with service account
- [mise](https://mise.jdx.dev/) for task management
- [OpenTofu](https://opentofu.org/) 1.6+
- Provider accounts (Cloudflare, Tailscale, B2, etc.)

### Token Setup

**Local**: Create `.mise.local.toml`:
```toml
[env]
OP_SERVICE_ACCOUNT_TOKEN = "ops_..."
TF_TOKEN_app_terraform_io = "..."
```

**GitHub**: Add as repository secrets in Settings → Secrets

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
# Format code
mise run fmt

# Validate configuration
mise run validate

# Plan changes
mise run plan                    # Both
mise run plan:infrastructure      # Infrastructure only
mise run plan:services           # Services only

# Apply changes
mise run apply                   # Both
mise run apply:infrastructure    # Infrastructure only
mise run apply:services          # Services only

# Check for drift
mise run refresh

# Clean up generated files
mise run clean
```

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
- [Development Guide](CLAUDE.md) - Standards and guidelines
- [DNS Management](DNS_ARCHITECTURE.md) - DNS strategy and patterns
- [Feature Matrix](FEATURE_MATRIX.md) - Complete configuration reference
- [Secrets Guide](SECRETS.md) - Required secrets configuration
- [Templates Guide](TEMPLATES.md) - Manual creation in 1Password

## License

This project is licensed under the AGPL-3.0 License - see the [LICENSE](LICENSE) file for details.
