# Operations

## Commands

```bash
mise run setup       # Create .mise.local.toml from the template
mise run init        # Initialize OpenTofu providers and backend
mise run plan        # Review infrastructure changes
mise run apply       # Apply infrastructure changes
mise run check       # Format check, lint, and validate
mise run fmt         # Format HCL, Python, YAML, schemas, and templates
mise run render      # Render plaintext deploy artifacts via debug_dir
```

## Adding Servers

1. Create `data/servers/<key>.yml` following `schemas/server.json`.
2. Fill in `platform`, `type`, `features`, `identity`, and `networking`.
3. Run `mise run plan` and review the diff before `mise run apply`.

## Adding Services

1. Create `data/services/<key>.yml` following `schemas/service.json`.
2. Fill in `identity`, `routing`, and either `targets` or `target_feature`.
3. Set `identity.service` only when templates or deploy artifacts exist.
4. Add templates under `templates/services/<identity.service>/` when needed.
5. Run `mise run plan` and review the diff before `mise run apply`.
