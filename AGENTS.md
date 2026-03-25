# AGENTS.md - Development Guide

## Project Overview

**Purpose**: Homelab infrastructure management using OpenTofu with Sveltia CMS as source of truth
**Status**: Active
**Language**: HCL (OpenTofu 1.10+), YAML

## Tech Stack

- **IaC**: OpenTofu 1.10+
- **CMS**: Sveltia CMS (admin UI for editing `data/` YAML files)
- **Credentials**: Bitwarden (via OpenTofu provider — no CLI required)
- **Formatting**: Prettier (YAML), `tofu fmt` (HCL)
- **Task Runner**: mise

## Data Flow

```
Sveltia CMS (admin/)
    │  edits
    ▼
data/
├── defaults.yml        # Global config (organization, domains, system) and schema defaults for servers/services
├── dns/*.yml           # DNS zones and manual records
├── incus/              # Incus profiles and projects
├── servers/*.yml       # Server definitions
└── services/*.yml      # Service deployments
    │  read by
    ▼
OpenTofu locals
    ├── servers.tf      deepmerge defaults + per-server YAML → local.servers
    └── services.tf     deepmerge defaults + per-service YAML → local.services (expanded per deploy_to target)
    │  provisions
    ▼
Providers
    ├── Bitwarden       One credential entry per server/service with all generated fields
    ├── B2              Object storage buckets and application keys
    ├── Cloudflare      DNS records, Zero Trust tunnels, ACME tokens
    ├── Incus           Profiles, projects, containers, VMs
    ├── OCI             Oracle Cloud VMs and networking
    ├── Komodo          SOPS-encrypted compose files + server/stack configs → GitHub repo
    ├── Resend          Email API keys
    └── Tailscale       VPN auth keys and device lookups
```

## Project Structure

- **`admin/`**: Sveltia CMS configuration (`config.yml`)
- **`data/`**: YAML source-of-truth files (edited via Sveltia CMS or directly)
- **`docker/`**: Docker Compose templates rendered by `komodo.tf` (one subdirectory per service)
- **`age.tf`**: age keypair generation per docker-enabled server (public key for SOPS, secret key stored in Bitwarden)
- **`b2.tf`**: Backblaze B2 buckets and application keys
- **`backend.tf`**: OpenTofu state backend (Terraform Cloud)
- **`bcrypt.tf`**: Bcrypt password hashing for server and service passwords
- **`bitwarden.tf`**: Credential storage — one Bitwarden entry per server/service
- **`cloud_config.tf`**: Renders cloud-init configs from `templates/cloud_config/cloud_config.yaml` for all servers (Incus containers/VMs and OCI instances)
- **`cloudflare.tf`**: DNS records, Zero Trust tunnels, ACME tokens
- **`dns.tf`**: DNS record locals (ACME delegation, manual, server, service, URL, wildcard)
- **`github.tf`**: Fetches SSH public keys from a GitHub user for injection into server cloud-init; also referenced by `komodo.tf` for repository file management
- **`incus.tf`**: Incus profiles, projects, containers, and VMs
- **`komodo.tf`**: Renders SOPS-encrypted Docker Compose files and pushes Komodo ResourceSync configs (servers/stacks) to a GitHub repository
- **`locals.tf`**: Shared locals and summary output
- **`oci.tf`**: Oracle Cloud VMs and networking
- **`providers.tf`**: Provider configurations and versions
- **`resend.tf`**: Resend email API keys
- **`servers.tf`**: Server locals — deepmerge, feature maps, validation
- **`services.tf`**: Service locals — deepmerge, deployment expansion, feature maps, validation
- **`talos.tf`**: Filtered locals for Talos nodes (control-plane/worker) — no resources provisioned yet
- **`tailscale.tf`**: Tailscale auth keys and device lookups
- **`terraform.tf`**: Required providers and OpenTofu version
- **`unifi.tf`**: UniFi client lookup stub (currently commented out — provides private IPs when enabled)
- **`variables.tf`**: Input variable definitions

## Code Standards

### Sorting Convention

Within any YAML or HCL object, apply this order:
1. `id` or `name` first
2. `description` second (if present)
3. All remaining **scalar** key/value pairs — grouped by semantic relationship, alphabetical within each group
4. All remaining **multi-line** objects and lists, alphabetical

This applies to: `data/defaults.yml`, `admin/config.yml` field definitions, HCL `locals {}` blocks, and resource attribute lists.

Top-level objects in `data/defaults.yml` are ordered: primary config groups (`organization`, `domains`, `system`) first, then service integrations and schema defaults alphabetically (`bitwarden`, `dns`, `github`, `incus`, `resend`, `servers`, `services`, `tailscale`).

### HCL

- **Formatting**: `tofu fmt -recursive` (run via `mise run fmt`)
- **`for_each`**: Always prefer over `count`
- **Naming**: `snake_case` for all resources, locals, and variables
- **Sensitive data**: Mark all secrets as `sensitive = true` in outputs
- **State**: Never manipulate state manually — use `tofu import` for imports
- **Validation**: Use `terraform_data` preconditions for referential integrity checks

### YAML

- **Formatting**: Prettier (run via `mise run fmt`)
- **Sorting**: Follow the sorting convention above
- **Defaults**: `data/defaults.yml` defines the full schema; per-resource files only override what differs

### General

- **Comments**: Minimal — only for non-obvious business logic
- **KISS**: Prefer readable over clever
- **Trailing newlines**: Required in all files

## Workflow

### Adding a Server

1. Open **Sveltia CMS** → Servers → New (or edit `data/servers/<id>.yml` directly)
2. Set `id`, `platform`, `type`, `features`, `identity`, `networking`
3. Commit via Sveltia CMS (or `git commit`)
4. Run `mise run plan` → `mise run apply`

### Adding a Service

1. Open **Sveltia CMS** → Services → New (or edit `data/services/<id>.yml` directly)
2. Set `id`, `deploy_to`, `features`, `identity`, `networking`
3. Commit via Sveltia CMS (or `git commit`)
4. Run `mise run plan` → `mise run apply`

### Adding Incus Profiles / Projects

1. Edit `data/incus/profiles/<name>.yml` or `data/incus/projects/<name>.yml`
2. Run `mise run plan` → `mise run apply`

## Commands

```bash
mise run setup     # Create .mise.local.toml from template
mise run init      # Initialize OpenTofu providers and backend

mise run check     # Format and validate (fmt + validate)
mise run fmt       # Format HCL and YAML data files
mise run validate  # Validate OpenTofu configuration

mise run refresh   # Check for configuration drift
mise run plan      # Review infrastructure changes
mise run apply     # Apply infrastructure changes
```

## Credential Storage

All generated credentials are stored automatically in **Bitwarden**:

- **Servers folder**: One login entry per server; generated fields (passwords, API keys, IPs, FQDNs, tunnel tokens) stored as custom fields
- **Services folder**: One login entry per service deployment with the same pattern

The Bitwarden entry `username` is set from `identity.username`; all other fields use custom field storage via the `bitwarden_item_login` resource in `bitwarden.tf`.

## Environment Setup

Run `mise run setup` to create `.mise.local.toml` from `.mise.local.toml.default`, then fill in all credentials.
