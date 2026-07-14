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

## Protected Resources

Age keys, B2 buckets, GitHub deployment repositories, and Incus and OCI
instances use `prevent_destroy`. Removing their source YAML or feature flag will
stop the apply instead of deleting the resource.

For an intentional deletion:

1. Back up the workload and its data. Before replacing an age key, retain a
   recovery copy or re-encrypt every artifact for the replacement key.
2. Remove `prevent_destroy` only from the relevant resource block.
3. Run `mise run plan` and confirm that the plan destroys only the intended
   addresses.
4. Apply the reviewed plan, then restore the guard if the resource block
   remains configured.

Do not combine temporary guard removal with unrelated infrastructure changes.
