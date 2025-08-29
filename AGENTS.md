# AGENTS.md - Development Guide

## Project Overview

**Purpose**: Unified homelab infrastructure and services management using OpenTofu with 1Password as single source of truth  
**Status**: Active  
**Language**: HCL (OpenTofu 1.8+)

## Code Standards

### Organization
- **Config/Data**: Alphabetical and recursive (imports, dependencies, object keys, mise tasks)
- **Documentation**: Sort sections, lists, and references alphabetically when logical
- **Files**: Alphabetical in documentation and directories
- **Functions**: Group by purpose, alphabetical within groups
- **Variables**: Alphabetical within scope

### Quality
- **Comments**: Minimal - only for complex business logic
- **Documentation**: Update ARCHITECTURE.md and README.md with every feature change
- **Error handling**: Use `nonsensitive()` for secrets, include resource names
- **Formatting**: Run `mise run fmt` before commits
- **KISS principle**: Keep it simple - prefer readable code over clever code
- **Naming**: snake_case for all HCL resources and variables
- **Testing**: Run `tofu validate` and `tofu plan` before commits
- **Trailing newlines**: Required in all files

## Commands

```bash
# Setup
mise run setup           # Create providers entry in 1Password
mise run init            # Initialize OpenTofu providers and backend

# Development
mise run check           # All validation (fmt + validate)
mise run fmt             # Format HCL files recursively
mise run validate        # Validate OpenTofu configuration

# Deployment
mise run refresh         # Check for configuration drift
mise run plan            # Review infrastructure changes
mise run apply           # Apply infrastructure changes
```

## Development Guidelines

### Contribution Standards
- **Code Changes**: Follow alphabetical sorting and maintain field schemas
- **Documentation**: Keep all docs synchronized and cross-referenced
- **Feature Changes**: Update README.md and ARCHITECTURE.md when adding features

### Documentation Structure
- **AGENTS.md**: Development standards and project guidelines
- **ARCHITECTURE.md**: Technical design and field reference
- **README.md**: Tool overview and usage guide
- **SECRETS.md**: Credential setup and management

## Development Workflow Standards

### 1Password Workflow
1. Create entry with proper naming convention
2. Run `apply` to generate input/output sections
3. Fill in input fields
4. Run `apply` again to provision resources

### Environment Management
- Define common tasks as mise scripts in `.mise.toml`
- Pin tool versions in `.mise.toml`
- Use **mise** for consistent development environments

## Error Handling Standards

- **Contextual errors**: Include resource name and operation in messages
- **Graceful degradation**: Continue with other resources if one fails
- **Informative messages**: Suggest fixes for common issues
- **User-friendly output**: Use `nonsensitive()` wrapper for error messages with secrets

## OpenTofu Standards

- **Resource naming**: Use `for_each` over `count` for all resources
- **Sensitive data**: Mark all secrets as sensitive in outputs
- **State management**: Never manipulate state manually except for imports
- **Validation**: Use preconditions for input validation

## Project Structure

- **b2.tf**: Backblaze B2 storage resources
- **cloudflare.tf**: DNS and tunnel management
- **homelab_*.tf**: Infrastructure discovery, processing, and sync
- **locals_dns.tf**: DNS record generation logic
- **providers.tf**: Provider configurations
- **resend.tf**: Email service resources
- **services_*.tf**: Service discovery, processing, and sync
- **tailscale.tf**: Zero-trust networking
- **templates/**: Configuration files
- **terraform.tf**: Backend configuration
- **variables.tf**: Variable definitions

## README Guidelines

- **Badges**: Include license, status, and OpenTofu version
- **Code examples**: Always include working commands
- **Installation**: Provide copy-paste setup commands
- **Quick Start**: Get users running in under 5 minutes
- **Structure**: Title → Badges → Description → Quick Start → Workflow → Documentation

## Tech Stack

- **IaC**: OpenTofu 1.8+
- **Secrets**: 1Password CLI
- **Task Runner**: mise
- **Version Control**: Git

---

*Development guide for the homelab infrastructure project.*
