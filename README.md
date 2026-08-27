# Homelab Pre-Kubernetes Archive

[![Licence](https://img.shields.io/badge/licence-AGPL--3.0-blue.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.x-blue)](https://opentofu.org/)
[![Status](https://img.shields.io/badge/status-archived-inactive)](https://github.com/maxexcloo/homelab)

> [!CAUTION]
> This branch is historical evidence. Do not initialise, plan, or apply its
> OpenTofu configuration.

The `main` branch owns the substrate required to rebuild or reach a cluster
while Kubernetes is unavailable. The `kubelab` repository owns Kubernetes
platform and workload resources reconciled by Flux.

The pre-Kubernetes service definitions remain here as rollback and migration
evidence. Previous workload containers are stopped and their data is retained
for the seven-day rollback window. The immutable `legacy` tag preserves the
original snapshot.

No GitHub workflow deploys this branch. Use `git show legacy:<path>` when the
original configuration is required for rollback analysis.

## Documentation

- [AGENTS.md](AGENTS.md) - Repository conventions for coding agents
- [docs/architecture.md](docs/architecture.md) - Data flow and deployment boundaries
- [docs/credentials.md](docs/credentials.md) - Credential storage and template access
- [docs/dashboard.md](docs/dashboard.md) - Homepage card and layout generation
- [docs/deployments.md](docs/deployments.md) - Rendered artefacts and deployment repositories
- [docs/features.md](docs/features.md) - Server and service feature flag effects
- [docs/observability.md](docs/observability.md) - Metrics collection and dashboards
- [docs/operations.md](docs/operations.md) - Common workflows and local commands
- [docs/routing.md](docs/routing.md) - URLs, DNS, Traefik labels, and containers
- [docs/servers.md](docs/servers.md) - Server inheritance, hostnames, and runtime values
- [docs/services.md](docs/services.md) - Service data, targets, routing, and templates
- [docs/truenas-services.md](docs/truenas-services.md) - TrueNAS catalog service authoring

## Licence

AGPL-3.0 - see [LICENSE](LICENSE).
