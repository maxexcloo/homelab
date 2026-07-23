# Operations

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
mise run render          # Render plaintext deploy artifacts via debug_dir
mise run setup           # Initial project setup and Git hook installation
mise run sort-check      # Check HCL local, JSON Schema, and YAML key ordering
mise run validate        # Check and validate OpenTofu configuration
```

Targeted commands include dependencies required by the selected module. Use the
full plan when checking for changes outside that module boundary.

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

`mise run setup` installs the local prek-managed Git hook. Use `mise run check`
for normal source validation and `mise run prek` for the complete hook suite.
Run `mise run hooks` only when the hook needs reinstalling.

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

Plan and apply remain operator-controlled.

## Intentional Exceptions

- The legacy Cloudflare ACME token remains available for clients, currently
  TrueNAS, that cannot follow delegated ACME CNAME records.
- Backblaze B2 application keys use the deprecated singular `bucket_id` field
  because `bucket_ids` cannot create an equivalent bucket-scoped key.
- Incus user data and OCI instance metadata ignore updates after creation
  because cloud-init consumes them only during first boot.
- Control D, 1Password, and Resend REST resources tolerate API-owned fields or
  changes so managed fields can reconcile without deleting unmanaged data.

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
