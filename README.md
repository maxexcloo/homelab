# Homelab

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.x-blue)](https://opentofu.org/)
[![Status](https://img.shields.io/badge/status-active-success)](https://github.com/maxexcloo/homelab)

OpenTofu manages this homelab from YAML in `data/`. It provisions resources and
renders encrypted deployment artifacts from the same source data.

The root configuration loads shared configuration and DNS data, then composes
two domain modules: `modules/servers` owns server modeling, runtime, and
infrastructure, while `modules/services` owns service modeling, runtime,
rendering, integrations, and deployment publications.

## Quick Start

```bash
git clone https://github.com/maxexcloo/homelab.git
cd homelab

mise run setup
mise run init
mise run check
mise run plan
mise run apply
```

Review the plan before applying it.

## Prerequisites

- [mise](https://mise.jdx.dev/) for task management and tool installation
- Optional 1Password Connect server with access to the server and service
  credential vaults in `data/config.yml`
- HCP Terraform account for the state backend

Run `mise run setup` to create `.mise.local.toml` from the template, then add
credentials for the providers used by the current data. See
`.mise.local.toml.default` for the full list.

Commit `.terraform.lock.hcl` when provider selections change. Keep the
`.terraform/` directory and plan or state files local.

## Commands

```bash
mise run apply           # Apply infrastructure changes
mise run apply-servers   # Apply server module changes
mise run apply-services  # Apply service module changes
mise run check           # Format check, lint, and validate
mise run fmt             # Format HCL, Python, YAML, schemas, and templates
mise run hooks           # Install Git hooks with prek
mise run init            # Initialize OpenTofu providers and backend
mise run lint            # Validate source and default-merged YAML against JSON schemas
mise run plan            # Review infrastructure changes
mise run plan-servers    # Review server module changes
mise run plan-services   # Review service module changes
mise run prek            # Run all repository hooks
mise run render          # Render plaintext deployment artifacts via debug_dir
mise run setup           # Initial project setup and Git hook installation
mise run sort-check      # Check HCL local, JSON Schema, and YAML key ordering
mise run validate        # Check and validate OpenTofu configuration
```

## Documentation

- [AGENTS.md](AGENTS.md) - Repository conventions for coding agents
- [docs/architecture.md](docs/architecture.md) - Data flow and deployment boundaries
- [docs/credentials.md](docs/credentials.md) - Credential storage and template access
- [docs/dashboard.md](docs/dashboard.md) - Homepage card and layout generation
- [docs/deployments.md](docs/deployments.md) - Rendered artifacts and deployment repositories
- [docs/features.md](docs/features.md) - Server and service feature flag effects
- [docs/operations.md](docs/operations.md) - Common workflows and local commands
- [docs/routing.md](docs/routing.md) - URLs, DNS, Traefik labels, and containers
- [docs/servers.md](docs/servers.md) - Server inheritance, hostnames, and runtime values
- [docs/service-rollout.md](docs/service-rollout.md) - Manual service rollout runbook
- [docs/services.md](docs/services.md) - Service data, targets, routing, and templates
- [docs/truenas-services.md](docs/truenas-services.md) - TrueNAS catalog service authoring

## License

AGPL-3.0 - see [LICENSE](LICENSE)
