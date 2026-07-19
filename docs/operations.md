# Operations

## Commands

```bash
mise run apply       # Apply infrastructure changes
mise run check       # Format check, lint, and validate
mise run fmt         # Format HCL, Python, YAML, schemas, and templates
mise run hooks       # Install Git hooks with prek
mise run init        # Initialize OpenTofu providers and backend
mise run lint        # Validate source and default-merged YAML against JSON schemas
mise run plan        # Review infrastructure changes
mise run prek        # Run all repository hooks
mise run render      # Render plaintext deploy artifacts via debug_dir
mise run setup       # Initial project setup and Git hook installation
mise run sort-check  # Check YAML and JSON Schema key ordering
mise run validate    # Check and validate OpenTofu configuration
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

## Automated Checks

`mise run setup` installs the local prek-managed Git hook. Use `mise run hooks`
to reinstall it, and `mise run prek` to run the complete suite on demand.

The hook suite checks file hygiene, GitHub Actions, Dockerfiles, concrete Docker
Compose files, JSON Schemas, Renovate configuration, OpenTofu formatting and
validation, Python, and source/default-merged YAML. Compose templates ending in
`.yaml.tftpl` are checked as OpenTofu templates; they are not passed to the
Compose schema until rendered because they still contain template expressions.

GitHub Actions runs prek for pull requests and pushes to `main`. Actions and
hook repositories use explicit release versions, while mise pins the executable
toolchain. The workflow initializes OpenTofu with the backend disabled, so
validation requires no Terraform Cloud token or provider credentials and is
safe for public pull requests.

Plan and apply remain operator-controlled. A future standalone delivery
workflow should create one saved plan with protected provider credentials,
retain it as the reviewed artifact, and apply that exact artifact only through
a protected environment with approval.

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
