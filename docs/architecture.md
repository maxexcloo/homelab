# Architecture

YAML in `data/` is the source of truth. OpenTofu validates it, builds stable
models, provisions infrastructure, and publishes non-secret deployment configs.
1Password Connect stores the credential inventory.

## Stages

Each server and service moves through four public boundaries:

1. Input loads YAML and applies defaults.
2. Model computes deterministic values used for identity, relationships,
   validation, and `for_each`.
3. Runtime adds provider-backed addresses, attributes, credentials, hosts, and
   URLs after resource membership is fixed.
4. Config publishes the minimum non-secret context used by deployment
   repositories.

Private resolution locals expand YAML template expressions between runtime and
config. They are an implementation detail, not another resource-identity layer.

Resource keys and collection membership must never depend on runtime values.
JSON Schema validates data shape; HCL preconditions validate relationships.

## Deployments

The root creates deployment repositories and publishes a `CONFIG` variable to
each one. Target repositories own their templates, workflows, rendering, and
deployment code.

- Docker publishes target-specific OCI packages for doco-cd and encrypts every
  deployment file with SOPS.
- Fly resolves credentials on a hosted runner and deploys with Fly tooling.
- TrueNAS renders and encrypts on a hosted runner, then decrypts and deploys on
  the matching self-hosted runner.

`CONFIG` contains no secret values. Credential fields are programmatic `op://`
references resolved by the target workflow.

## Modules

- `modules/credentials` generates provider-consumed scalar credentials, hashes,
  and X.509 material.
- `modules/object_storage` provisions isolated object-storage credentials.
- `modules/onepassword` finds generic 1Password Connect items and reads values
  still required by OpenTofu consumers.
- `modules/resend` creates idempotent Resend API keys for servers and services.

Server and service pipelines live in root because each was used exactly once
and their interfaces added indirection without reuse. Leaf modules remain for
repeated resource groups. The root also owns shared DNS, routing, repositories,
and cross-domain provider data.
