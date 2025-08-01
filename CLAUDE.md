# CLAUDE.md - Development Guide

## Project Overview
**Purpose**: Unified homelab infrastructure and services management using OpenTofu with 1Password as single source of truth
**Status**: Active
**Language**: HCL (OpenTofu/Terraform)

## Code Standards

### Organization
- **Config/Data**: Alphabetical and recursive (imports, dependencies, object keys, mise tasks)
- **Documentation**: Sort sections, lists, and references alphabetically when logical
- **Files**: Alphabetical in documentation and directories
- **Functions**: Group by purpose, alphabetical within groups
- **Variables**: Alphabetical within scope
- **HCL Blocks**: Simple values first (alphabetically), then complex blocks (alphabetically)
- **1Password Entries**: Inputs/outputs sections with recursive alphabetical sorting

### Quality
- **Comments**: Minimal - only for complex business logic
- **Documentation**: Update ARCHITECTURE.md, FEATURE_MATRIX.md, and README.md with every feature change
- **Error handling**: Graceful degradation with informative error messages
- **Formatting**: Run `mise run fmt` before commits
- **KISS principle**: Keep it simple - prefer readable code over clever code
- **Naming**: snake_case for all HCL resources and variables
- **Testing**: `tofu validate` and `tofu plan` before all commits
- **Trailing newlines**: Required in all files

## Commands
```bash
# Setup
mise run setup          # Initial project setup

# Initialize
mise run init           # Initialize OpenTofu

# Plan & Apply
mise run plan           # Plan all changes
mise run apply          # Apply all changes

# Utilities
mise run fmt            # Format all files
mise run validate       # Validate configuration
mise run clean          # Clean up generated files

# Create Resources
mise run server <region>-<name> <type>  # Create server
mise run service <platform>-<name>      # Create service
mise run list                           # List infrastructure
```

## Development Guidelines

### Contribution Standards
- **Code Changes**: Follow sorting rules and maintain [specific requirements]
- **Documentation**: Keep all docs synchronized and cross-referenced
- **Feature Changes**: Update README.md and ARCHITECTURE.md when adding features

### Documentation Structure
- **ARCHITECTURE.md**: Technical design and implementation details
- **CLAUDE.md**: Development standards and project guidelines
- **README.md**: Tool overview and usage guide

## 1Password Entry Standards

### Service Entries (Services Vault)
- **Naming**: `platform-service` (e.g., docker-grafana, fly-app)
- **Sections**: inputs, platform-specific (docker, fly), outputs
- **No Server Suffix**: Services are shared across deployments

### Server Entries (Infrastructure Vault)
- **Naming**: `server-region-name` (e.g., server-au-hsp)
- **Sections**: inputs, type-specific (oci, proxmox), outputs
- **Platform Field**: ubuntu, truenas, haos, pbs, mac, proxmox, pikvm

### DNS Zone Entries (Infrastructure Vault)
- **Naming**: `dns-domain-tld` (e.g., dns-excloo-com)
- **Sections**: inputs (zone config), records (manual DNS), outputs
- **Auto-sync**: Zone IDs from Cloudflare

### Sorting Rules
- **Simple Before Complex**: Strings/numbers before arrays/objects
- **Alphabetical**: Within each complexity level
- **Recursive**: Apply to all nested structures

## Development Workflow Standards

### Environment Management
- Use **mise** for consistent development environments
- Define common tasks as mise scripts in `.mise.toml`
- Pin tool versions in `.mise.toml`

## Error Handling Standards
- **Contextual errors**: Include resource name and operation in error messages
- **Graceful degradation**: Continue with other resources if one fails
- **Informative messages**: Suggest fixes for common issues
- **User-friendly output**: Clear explanation of what went wrong and next steps

### Required Development Tasks
- **apply**: Apply all changes with confirmation
- **fmt**: Format all HCL files recursively
- **init**: Initialize OpenTofu backends and providers
- **plan**: Generate plans for review
- **setup**: Initial project setup with 1Password
- **validate**: Validate HCL syntax and configuration

## Project Structure
- **infrastructure/**: Server and infrastructure resource definitions
- **modules/**: Reusable OpenTofu modules for servers, services, features
- **services/**: Service deployment configurations
- **templates/**: Configuration templates for services (docker-compose, etc.)
- **.github/workflows/**: GitHub Actions for plan/apply workflows
- **.mise.toml**: Local development task definitions
- **ARCHITECTURE.md**: System design and data flows
- **DNS_ARCHITECTURE.md**: DNS management strategy
- **FEATURE_MATRIX.md**: Complete feature and configuration reference

## README Guidelines
- **Badges**: Include relevant status badges (license, status, docker, language)
- **Code examples**: Always include working examples in code blocks
- **Installation**: Provide copy-paste commands that work
- **Quick Start**: Get users running in under 5 minutes
- **Structure**: Title → Badges → Description → Quick Start → Features → Installation → Usage → Contributing

## Tech Stack
- **IaC**: OpenTofu (Terraform-compatible)
- **Secret Management**: 1Password with service accounts
- **State Backend**: Backblaze B2 (S3-compatible)
- **Container Orchestration**: Komodo (Docker management)
- **Platforms**: Docker, Fly.io, Cloudflare Workers
- **Monitoring**: Gatus (health checks), Homepage (dashboard)
- **Networking**: Tailscale (zero-trust mesh), Cloudflare (DNS/tunnels)

---

*Development guide for the [project-name] open source project.*
