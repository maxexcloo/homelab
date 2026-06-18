# Homelab

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.x-blue)](https://opentofu.org/)
[![Status](https://img.shields.io/badge/status-active-success)](https://github.com/maxexcloo/homelab)

Infrastructure as code for homelab management using OpenTofu. YAML files in
`data/` describe the desired state; OpenTofu provisions resources and renders
encrypted deployment artifacts.

## Quick Start

```bash
git clone https://github.com/maxexcloo/homelab.git
cd homelab

mise run setup
mise run init

mise run plan
mise run apply
```

## Prerequisites

- [mise](https://mise.jdx.dev/) for task management and tool installation
- 1Password Connect server with access to the server and service credential vaults listed in `data/config.yml`
- Terraform Cloud account for state backend

Run `mise run setup` to create `.mise.local.toml` from the template, then fill in credentials for the providers used by the current data files. See `.mise.local.toml.default` for the full list.

The provider lock file (`.terraform.lock.hcl`) should be committed when provider selections change. The `.terraform/` plugin directory and any plan/state files stay local.

## Commands

```bash
mise run apply       # Apply infrastructure changes
mise run check       # Format check, lint, and validate
mise run fmt         # Format HCL, Python, YAML, schemas, and templates
mise run init        # Initialize OpenTofu providers and backend
mise run lint        # Validate source and default-merged YAML against JSON schemas
mise run plan        # Review infrastructure changes
mise run setup       # Initial project setup
mise run sort-check  # Check YAML and JSON Schema key ordering
mise run validate    # Validate OpenTofu configuration
```

## Documentation

- [docs/architecture.md](docs/architecture.md) - Data flow and deployment boundaries
- [docs/credentials.md](docs/credentials.md) - Credential storage and template access
- [docs/dashboard.md](docs/dashboard.md) - Homepage card and layout generation
- [docs/deployments.md](docs/deployments.md) - Rendered artifacts and deployment repositories
- [docs/features.md](docs/features.md) - Server and service feature flag effects
- [docs/operations.md](docs/operations.md) - Common workflows and local commands
- [docs/routing.md](docs/routing.md) - URLs, DNS, Traefik labels, and containers
- [docs/servers.md](docs/servers.md) - Server inheritance, hostnames, and runtime values
- [docs/services.md](docs/services.md) - Service data, targets, routing, and templates
- [AGENTS.md](AGENTS.md) - Development guide and standards

## License

AGPL-3.0 - see [LICENSE](LICENSE)
