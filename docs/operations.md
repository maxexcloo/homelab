# Operations

## Commands

```bash
mise run apply           # Apply infrastructure changes
mise run check           # Format check, lint, and validate
mise run cleanup         # Remove rendered artefacts, caches, bytecode, and saved plans
mise run fmt             # Format HCL, Python, YAML, schemas, and templates
mise run init            # Initialise OpenTofu providers and backend
mise run lint            # Validate source and default-merged YAML against JSON schemas
mise run plan            # Review infrastructure changes
mise run prek            # Run all repository hooks
mise run setup           # Clean, configure, initialise, and install Git hooks
mise run sort-check      # Check HCL local, JSON Schema, and YAML key ordering
mise run validate        # Check and validate OpenTofu configuration
```

## State Backend

OpenTofu uses GCS with Google Application Default Credentials. The mise-managed
`gcloud` CLI can establish those credentials with
`gcloud auth application-default login`.

## Adding Servers

1. Create `data/servers/<key>.yaml` following `schemas/server.json`.
2. Fill in `platform`, `type`, `features`, `identity`, and `networking`.
3. Run `mise run plan` and review the diff before `mise run apply`.

## Adding Services

1. Create `data/services/<key>.yaml` following `schemas/service.json`.
2. Fill in `identity`, `routing`, and either `targets` or `target_feature`.
3. Set `identity.service` only when templates or deploy artefacts exist.
4. Add deployment templates to the repository that owns the target platform.
5. Run `mise run plan` and review the diff before `mise run apply`.

## Automated Checks

`mise run setup` cleans generated files, creates the local configuration when
missing, initialises OpenTofu, and installs the prek-managed Git hook. Use
`mise run check` for normal source validation and `mise run prek` for the
complete hook suite.

The hook suite checks file hygiene, GitHub Actions, Dockerfiles, concrete Docker
Compose files, JSON Schemas, Renovate configuration, OpenTofu formatting and
validation, Python, and source/default-merged YAML. Compose templates ending in
`.yaml.tftpl` are checked as OpenTofu templates; they are not passed to the
Compose schema until rendered because they still contain template expressions.

GitHub Actions runs prek for pull requests and pushes to `main`. Actions and
hook repositories use explicit release versions, while mise pins the executable
toolchain. The workflow initialises OpenTofu with the backend disabled, so
validation requires no GCP or provider credentials and is safe for public pull
requests.

Plan and apply remain operator-controlled.

## Intentional Exceptions

- The legacy Cloudflare ACME token remains available for clients, currently
  TrueNAS, that cannot follow delegated ACME CNAME records.
- Backblaze B2 application keys use the deprecated singular `bucket_id` field
  because `bucket_ids` cannot create an equivalent bucket-scoped key.
- Incus user data and OCI instance metadata ignore updates after creation
  because cloud-init consumes them only during first boot.
- Control D and Resend REST resources tolerate API-owned fields or changes so
  managed fields can reconcile without deleting unmanaged data.

## Destructive Changes

Age keys, B2 buckets, GitHub deployment repositories, and Incus and OCI
instances can all be destroyed. Removing their source YAML or feature flag can
therefore delete the resource on the next apply.

For an intentional deletion:

1. Back up the workload and its data. Before replacing an age key, retain a
   recovery copy or re-encrypt every artefact for the replacement key.
2. Run `mise run plan` and confirm that the plan destroys only the intended
   addresses.
3. Apply only the reviewed plan.

Do not combine destructive changes with unrelated infrastructure changes.
