# Homelab

[![Licence](https://img.shields.io/badge/licence-AGPL--3.0-blue.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.x-blue)](https://opentofu.org/)
[![Status](https://img.shields.io/badge/status-active-success)](https://github.com/maxexcloo/homelab)

OpenTofu manages this homelab from YAML in `data/`. It provisions resources and
publishes non-secret deployment config from the same source data.

Server and service pipelines live directly in the root configuration. Small
leaf modules remain only for repeated resource groups such as credentials,
object storage, and 1Password item reconciliation. Platform repositories own
their templates, rendering, and deployment workflows.

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

- 1Password Connect server with access to the server and service
  credential vaults in `data/config.yaml`
- Google Application Default Credentials for the GCS state backend
- [mise](https://mise.jdx.dev/) for task management and tool installation
- Pocket ID instance and API token

Run `mise run setup` to remove local OpenTofu data, the Ruff cache, and any
saved `tfplan`; create `.mise.local.toml` from the template; initialise
OpenTofu; and install the Git hook. On first run, add the required credentials
and run setup again. See `.mise.local.toml.default` for the full variable list.

Commit `.terraform.lock.hcl` when provider selections change. Keep the
`.terraform/` directory and plan or state files local.

## Commands

```bash
mise run apply           # Apply infrastructure changes
mise run check           # Format check, lint, and validate
mise run cleanup         # Remove local OpenTofu data, the Ruff cache, and the saved plan
mise run fmt             # Format HCL, Python, YAML, schemas, and templates
mise run init            # Initialise OpenTofu providers and backend
mise run lint            # Lint Python and validate YAML against JSON schemas
mise run plan            # Review infrastructure changes
mise run prek            # Run all repository hooks
mise run setup           # Clean local data, configure, initialise, and install Git hooks
mise run sort-check      # Check HCL assignments, JSON Schema, and YAML key ordering
mise run validate        # Check and validate OpenTofu configuration
```

## Documentation

- [AGENTS.md](AGENTS.md) - Repository conventions for coding agents
- [docs/architecture.md](docs/architecture.md) - Data flow and deployment boundaries
- [docs/credentials.md](docs/credentials.md) - Credential storage and template access
- [docs/dashboard.md](docs/dashboard.md) - Homepage card and layout generation
- [docs/deployments.md](docs/deployments.md) - Rendered artefacts and deployment repositories
- [docs/features.md](docs/features.md) - Server and service feature flag effects
- [docs/operations.md](docs/operations.md) - Common workflows and local commands
- [docs/routing.md](docs/routing.md) - URLs, DNS, Traefik labels, and containers
- [docs/servers.md](docs/servers.md) - Server inheritance, hostnames, and runtime values
- [docs/services.md](docs/services.md) - Service data, targets, routing, and templates
- [docs/truenas-services.md](docs/truenas-services.md) - TrueNAS catalog service authoring

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
