# Architecture

YAML in `data/` is the source of truth. OpenTofu validates it, builds stable
models, provisions infrastructure, stores credentials in 1Password, and
publishes non-secret deployment configs.

## Stages

Each server and service moves through three boundaries:

1. Input loads YAML and applies defaults.
2. Model computes deterministic values used for identity, relationships,
   validation, and `for_each`.
3. Runtime adds provider-backed addresses, attributes, credentials, hosts, and
   URLs after resource membership is fixed.

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

- `modules/credentials` generates scalar credentials, hashes, and X.509 material.
- `modules/object_storage` provisions isolated object-storage credentials.
- `modules/onepassword` manages generic 1Password Connect items.
- `modules/servers` owns server models, infrastructure, and bootstrap output.
- `modules/services` owns service models and provider-backed service resources.

The root composes both domains and owns shared DNS, routing, repositories, and
cross-domain provider data.
