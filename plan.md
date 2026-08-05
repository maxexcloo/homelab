# Homelab Simplification Plan

## Current Scope Override

Client-side OpenTofu state and plan encryption is explicitly deferred. Do not
create an encryption passphrase, a dedicated encryption item or vault, or
`encryption.tf` during the current simplification work. GCS server-side
encryption, uniform bucket-level access, public access prevention, narrow IAM,
and Object Versioning are the current controls.

Sections 6, 7, 12, 13, and the encrypted delivery workflow in section 15 are
future work only. Their encryption requirements are not current dependencies or
completion gates. Do not upload saved plan or state artifacts while encryption
is deferred.

The isolated GCS version-restore drill and a dedicated recovery runbook are
also skipped in the current scope. The absence of a tested restore procedure is
an accepted temporary limitation.

## Repository Maintenance Rules

- Use `mise run check` as the single repository check entry point; it may
  delegate to Prek when that avoids duplicated orchestration.
- Keep Prek useful and small: repository hygiene, formatters, linters, and
  schema checks only, with no checker executed twice in one path.
- Prefer Renovate's recommended defaults, add only project-specific overrides,
  and group compatible updates by ecosystem.
- Keep tool, action, hook, and image pins current through Renovate where
  supported.
- Sort mise tools and tasks, Prek hooks, and Renovate rules alphabetically
  within their semantic groups.
- Use `.yaml`, never `.yml`, across homelab repositories.
- Treat 1Password Connect as required. OpenTofu automatically creates and
  reconciles server and service items during apply.
- Keep full 1Password item responses out of OpenTofu state. Persist only fields
  that OpenTofu genuinely consumes.
- Track field and URL ownership in each item. Delete removed OpenTofu-owned
  values and abandoned empty placeholders, while preserving populated manual
  placeholders and unknown fields.

1. **Lock the architectural decisions before changing code.**

   - OpenTofu version floor: `1.12.5`, matching the existing `mise` pin.
   - Primary backend: Google Cloud Storage.
   - Bucket region: `australia-southeast1` Sydney.
   - One active backend per OpenTofu root; R2 may later hold backups, never live mirrored state.
   - Repositories remain private.
   - GitHub Actions remains the CI control plane.
   - Existing self-hosted runners remain the execution layer.
   - 1Password remains the credential system of record.
   - 1Password Connect remains because it supports the required network and vault behavior.
   - No remote or cross-network Docker socket access.
   - Provider-managed services such as B2, Resend, Pocket ID, Cloudflare, and Tailscale remain supported.
   - Backend migration, secret refactoring, repository splitting, and state splitting happen in separate phases.
   - Client-side state and plan encryption is deferred until explicitly resumed.

2. **Treat GCS as effectively inexpensive, but not technically free in Sydney.**

   - Google's Always Free Cloud Storage allowance only applies to `us-east1`, `us-central1`, and `us-west1`; Sydney is excluded. [Google Cloud Free Tier](https://docs.cloud.google.com/free/docs/free-cloud-features)
   - Sydney Standard storage is approximately US$0.022/GiB-month at current pricing. [Cloud Storage pricing](https://cloud.google.com/storage/pricing)
   - The current state is approximately 6.12 MB, or 0.0057 GiB.
   - One live state copy costs roughly US$0.00013/month.
   - One hundred retained state generations would be roughly 0.57 GiB, around US$0.013/month.
   - Requests and Australian Internet transfer will likely cost more than storage, but at homelab plan/apply frequency should still remain in the cents-per-month range.
   - Create a US$1/month billing budget alert. Google budgets notify; they do not impose a hard spending cap.
   - Do not choose a US free-tier region merely to avoid cents: latency rises and transfer from North America to Australia is not included in the free allowance.

3. **Use this final repository ownership model.**

   | Repository | Final responsibility | GCS state prefix |
   | --- | --- | --- |
   | `homelab` | Shared network, zones, servers, account-level resources, GitHub repository governance | `states/core` |
   | `homelab-fly` | Fly services, templates, service-scoped external resources, deployment | `states/fly` |
   | `homelab-truenas` | TrueNAS services, templates, sidecars, service-scoped resources, deployment | `states/truenas` |
   | `homelab-docker` | Docker/doco-cd services and templates | `states/docker` |
   | `homelab-workflows` | Cross-target maintenance jobs only | State only if it eventually owns resources |

   Core owns account-level resources; target repositories own service-level resources. For example:

   - Core owns a Cloudflare zone; the target repo owns the DNS record for its service.
   - Core owns the Resend account/domain; the target repo owns a service-specific API key.
   - Core owns the B2 account credentials; the target repo owns a service-specific bucket and application key.
   - Core owns shared Pocket ID configuration; the target repo owns the service's OIDC client.
   - GitHub repository settings can remain in core, but repository files and workflows must become normally authored files in their respective repositories.

4. **Bootstrap the GCP project and bucket manually.**

   Use a dedicated or otherwise quiet GCP project with billing enabled. Suggested names:

   - Project: user-selected.
   - Bucket: globally unique, such as `excloo-opentofu-state`.
   - Region: `australia-southeast1`.
   - Storage class: `STANDARD`.

   Configure the bucket with:

   - Uniform bucket-level access.
   - Public access prevention enforced.
   - Object Versioning enabled.
   - Soft delete enabled for 14 days.
   - Google-managed server-side encryption.
   - No public ACLs.
   - No bucket-wide retention lock: OpenTofu must be able to delete lock objects.
   - No unrelated files in the state bucket.

   Configure lifecycle management for noncurrent versions:

   - Delete a noncurrent version only when it is at least 90 days old.
   - Retain at least 50 newer versions.
   - Let soft delete retain lifecycle-deleted versions for the additional 14-day window.
   - This also eventually removes historical lock-object generations.

   Google recommends versioning or soft delete for recovery, and they can be used together. [GCS Object Versioning](https://docs.cloud.google.com/storage/docs/object-versioning) [GCS soft delete](https://docs.cloud.google.com/storage/docs/soft-delete)

5. **Bootstrap GCP identities separately from the main OpenTofu root.**

   Create a service account such as:

   ```text
   opentofu-state@PROJECT_ID.iam.gserviceaccount.com
   ```

   Grant it only:

   ```text
   roles/storage.objectAdmin
   ```

   scoped to the state bucket. It should not be a project owner, storage administrator, or bucket administrator.

   For initial local migration:

   - Authenticate with `gcloud auth application-default login`.
   - Either use that identity directly or impersonate the state service account.
   - Prefer `GOOGLE_BACKEND_IMPERSONATE_SERVICE_ACCOUNT` over a downloaded service-account key.

   For GitHub Actions later:

   - Create a Workload Identity Pool and GitHub OIDC provider.
   - Restrict the provider to the `maxexcloo` owner and exact private repositories.
   - Use Workload Identity Federation through the dedicated service account.
   - Grant `roles/iam.workloadIdentityUser` only to those repository principals.
   - Use `google-github-actions/auth@v3`.
   - Do not create a permanent GCP service-account JSON key unless WIF proves impractical.

   Workload Identity Federation avoids long-lived cloud keys and supports GitHub Actions. [Google WIF](https://docs.cloud.google.com/iam/docs/workload-identity-federation) [Google GitHub auth action](https://github.com/google-github-actions/auth)

6. **[Deferred] Prepare a dedicated 1Password item for state encryption.**

   Do not implement this section during the current simplification work.

   Add an `Automation` or `Infrastructure` vault rather than mixing backend credentials with the existing Servers and Services vaults.

   Create:

   ```text
   Vault: Automation
   Item: opentofu-state-homelab
   Category: Login or Secure Note
   ```

   Fields:

   ```text
   credentials.encryption_passphrase
   metadata.managed_by
   metadata.resource_key
   metadata.schema_version
   ```

   Recommended values:

   ```text
   managed_by = homelab
   resource_key = opentofu-state-homelab
   schema_version = 1
   ```

   Generate a long random passphrase of at least 64 characters. Store a second offline recovery copy because losing it makes encrypted state unrecoverable.

   The stable reference should be:

   ```text
   op://Automation/opentofu-state-homelab/credentials/encryption_passphrase
   ```

   GCP project ID, bucket name, region, and state prefixes stay in Git because they are configuration, not secrets.

7. **[Deferred] Make the OpenTofu version requirement match the encryption requirement.**

   Do not change the version constraint solely for encryption while encryption is deferred.

   In `terraform.tf`, change the current broad floor:

   ```hcl
   required_version = "~> 1.11"
   ```

   to:

   ```hcl
   required_version = "~> 1.12.5"
   ```

   Keep `opentofu = "1.12.5"` in `.mise.toml`.

   Do this as part of migration preparation, but do not update provider versions or refactor resources in the same change.

8. **Capture a complete pre-migration baseline.**

   Before changing `backend.tf`:

   - Stop all applies.
   - Lock or disable runs in the HCP workspace.
   - Confirm no local apply or generated-repository workflow is active.
   - Record:
     - OpenTofu version.
     - Current workspace.
     - HCP organization and workspace.
     - State lineage and serial.
     - Full sorted `tofu state list`.
     - State byte size.
     - Current commit SHA.
     - Current provider lockfile hash.
   - Run `mise run check`.
   - Run a normal plan and require no unexpected changes.
   - Pull a state backup into a mode-`0600` temporary directory.
   - Encrypt that backup immediately with an offline age/SOPS recovery key.
   - Never commit, upload as a normal GitHub artifact, or leave the plaintext backup behind.

   The baseline becomes the acceptance comparison after migration.

9. **Test GCS with an isolated disposable state before migration.**

   Create a temporary OpenTofu root using:

   ```text
   states/backend-test
   ```

   Verify:

   - Initialization succeeds.
   - State can be written and read.
   - Two simultaneous operations cannot acquire the same lock.
   - The second operation receives a lock error rather than continuing.
   - The lock disappears after the first operation exits.
   - A previous object generation can be copied into a separate test prefix and read.
   - The temporary live state, lock, and test generations are removed afterward.

   This reproduces the test that disqualified B2, but against GCS. OpenTofu's GCS backend officially supports locking and recommends Object Versioning. [OpenTofu GCS backend](https://opentofu.org/docs/language/settings/backends/gcs/)

10. **Migrate HCP state to GCS as a backend-only change.**

    Replace the `cloud` block in `backend.tf` with:

    ```hcl
    terraform {
      backend "gcs" {
        bucket = "YOUR_GLOBALLY_UNIQUE_BUCKET"
        prefix = "states/core"
      }
    }
    ```

    Do not place credentials, access tokens, encryption keys, or service-account JSON in this block.

    Migration procedure:

    1. Confirm the apply freeze.
    2. Confirm the secure backup exists.
    3. Confirm both HCP and GCS authentication work.
    4. Run `tofu init -migrate-state` interactively.
    5. Accept only the expected HCP-to-GCS copy.
    6. Record the new GCS object generation.
    7. Compare the complete before/after state address lists.
    8. Confirm lineage is preserved.
    9. Run `tofu plan -detailed-exitcode`.
    10. Require exit code `0`.
    11. Repeat the lock contention test.
    12. Keep HCP read-only; do not delete the workspace.

    Do not use `-reconfigure`, `state push -force`, or combine this with service changes.

11. **Keep HCP as the rollback backend temporarily.**

    Retain the HCP workspace and token for at least 30 days.

    During this window:

    - HCP is read-only and must not receive new applies.
    - GCS is the only active backend.
    - The HCP token remains in 1Password but is removed from normal local and CI environments.
    - Every GCS apply is recorded with its object generation.
    - Restore testing must pass before HCP deletion.

    Rollback, if required before new GCS applies:

    1. Freeze GCS operations.
    2. Restore the old `cloud` block.
    3. Run `tofu init -migrate-state`.
    4. Compare lineage, serial, and addresses.
    5. Run a no-change plan.

    If GCS has already accepted state changes, migrate the latest GCS state back rather than simply reopening the stale HCP workspace.

12. **[Deferred] Enable OpenTofu client-side encryption in a separate phase.**

    Do not implement this section until client-side encryption is explicitly resumed.

    Add a sensitive root variable in `variables.tf`:

    ```hcl
    variable "state_encryption_passphrase" {
      description = "Passphrase used for OpenTofu state and plan encryption"
      sensitive   = true
      type        = string
    }
    ```

    Supply it as:

    ```text
    TF_VAR_state_encryption_passphrase
    ```

    loaded from the stable 1Password reference.

    Add a dedicated `encryption.tf` with:

    - A PBKDF2 key provider.
    - Explicit `encrypted_metadata_alias`, such as `homelab-state`.
    - AES-GCM encryption.
    - State encryption.
    - Plan encryption.
    - A temporary unencrypted fallback for reading the existing GCS state.

    First encryption change:

    ```hcl
    terraform {
      encryption {
        key_provider "pbkdf2" "state" {
          encrypted_metadata_alias = "homelab-state"
          passphrase               = var.state_encryption_passphrase
        }

        method "aes_gcm" "state" {
          keys = key_provider.pbkdf2.state
        }

        method "unencrypted" "migration" {}

        state {
          method = method.aes_gcm.state

          fallback {
            method = method.unencrypted.migration
          }
        }

        plan {
          enforced = true
          method   = method.aes_gcm.state
        }
      }
    }
    ```

    Then:

    1. Remove all old saved plans.
    2. Run a reviewed no-change plan and apply to rewrite state.
    3. Verify the newest raw GCS object is OpenTofu ciphertext, not JSON.
    4. Verify OpenTofu can still read it using the 1Password passphrase.
    5. Identify the original unencrypted GCS generation.
    6. Delete that noncurrent plaintext generation after the rollback checkpoint.
    7. Allow its soft-delete retention period to expire.
    8. Remove the `unencrypted` method and fallback.
    9. Add `enforced = true` to state encryption.
    10. Run another no-change plan.

    Do not rename the key provider, method, or metadata alias later. OpenTofu records those identifiers in encrypted metadata. [OpenTofu state and plan encryption](https://opentofu.org/docs/v1.12/language/state/encryption/)

13. **[Deferred] Perform an encrypted restore drill.**

    Do not implement this section until client-side encryption is explicitly resumed.

    Do not test recovery by overwriting live state.

    Instead:

    - Choose a known-good noncurrent GCS generation.
    - Copy it to `states/restore-test`.
    - Initialize an isolated checkout against that prefix.
    - Load the encryption passphrase from 1Password.
    - Run `tofu state list`.
    - Compare its addresses with the live state.
    - Run `tofu plan -refresh=false` only if needed to confirm readability.
    - Remove the restore-test objects afterward.

    Document:

    - How to locate GCS generations.
    - How to restore a generation.
    - How to supply the passphrase.
    - How to recover if 1Password Connect is unavailable.
    - Where the offline passphrase recovery copy is stored.

14. **Keep pull-request CI credential-free.**

    The existing `.github/workflows/prek.yaml` should continue to:

    - Run on GitHub-hosted runners.
    - Use `tofu init -backend=false`.
    - Run formatting, schema validation, linting, and static checks.
    - Have no GCP identity.
    - Have no 1Password Connect token.
    - Have no provider credentials.
    - Have no self-hosted runner access.

    This lets pull requests validate untrusted changes without exposing infrastructure access.

15. **[Deferred] Add a separate protected delivery workflow after GCS and encryption are stable.**

    Do not implement the saved-plan delivery workflow while plan encryption is deferred. Continue using reviewed local plans and explicitly approved local applies; never upload an unencrypted saved plan as a substitute.

    Delivery should run only:

    - On `workflow_dispatch`.
    - From the protected `main` branch.
    - In private repositories.
    - With `concurrency.cancel-in-progress: false`.
    - Through an approved GitHub environment.

    Plan job:

    1. Check out the exact main commit.
    2. Authenticate to GCP with `google-github-actions/auth@v3`.
    3. Load required secrets from 1Password Connect.
    4. Install the pinned `mise` toolchain.
    5. Run `tofu init`.
    6. Run `mise run check`.
    7. Produce an encrypted saved plan.
    8. Calculate its SHA-256 hash.
    9. Upload only the encrypted plan and redacted human-readable summary.
    10. Retain the artifact for one day.

    Apply job:

    1. Requires environment approval.
    2. Checks out the identical commit.
    3. Authenticates again using WIF.
    4. Loads the same encryption passphrase from 1Password.
    5. Downloads the exact plan.
    6. Verifies its SHA-256 hash.
    7. Applies that plan rather than generating another.
    8. Records the resulting GCS generation.
    9. Runs narrowly scoped post-apply health checks.

    Workflow permissions:

    ```yaml
    permissions:
      contents: read
      id-token: write
    ```

    Never upload raw state, unencrypted plan JSON, complete `tofu output -json`, or full 1Password item JSON.

16. **Define the permanent 1Password schema before moving credentials.**

    Status: the metadata inventory and field-label normalization are complete.
    Existing item titles, IDs, values, purposes, URLs, categories, and vaults
    were preserved.

    Keep the existing title convention:

    ```text
    Display Name (resource-key)
    ```

    The trailing parenthesized resource key is the programmatic identity. Keep
    the complete title stable, validate the convention, and reject duplicate
    resource keys within a vault. Do not rename existing items.

    Use the existing vault separation:

    - `Servers`
    - `Services`

    Standard sections:

    ```text
    credentials
    identifiers
    metadata
    ```

    Standard field rules:

    - All machine-facing labels use `snake_case`.
    - Field ID and field label match where possible.
    - No `_ro` or `_rw` suffix in the 1Password label.
    - Ownership mode remains in repository configuration, not the field name.
    - Names are never changed casually because references depend on them.
    - Multiple URLs use native 1Password URL entries.

    Example service item:

    ```text
    Item: Beszel (beszel-au-truenas)

    credentials.monitoring_token
    credentials.object_storage_secret_access_key
    credentials.oidc_client_secret
    credentials.password

    identifiers.object_storage_access_key_id
    identifiers.oidc_client_id

    metadata.managed_by
    metadata.owner_repository
    metadata.resource_key
    metadata.schema_version

    URL labels:
    default
    internal
    external
    admin
    ```

    Preserve the existing category, tags, and URLs unless a consumer requires a
    deliberate change.

17. **Reconcile 1Password through an OpenTofu-owned Connect boundary.**

    Status: implemented, applied, and verified with a no-change follow-up plan.
    Connect is required. OpenTofu invokes one ownership-aware reconciler when a
    server or service manifest changes, creates missing items during the same
    apply, and resolves only missing item IDs after reconciliation. Existing IDs
    remain known so unrelated deployment workflows are not retriggered.

    Full item responses stay in reconciler memory. OpenTofu persists only the
    selected manual fields it genuinely consumes, provider-owned values already
    present in state, item IDs, and manifest hashes.

    The `op` CLI does not use Connect as its item CRUD transport. Keep Connect
    as the reconciliation writer and multi-vault API. A target deployment may
    use the official `op` CLI with a dedicated read-only service account when
    it needs only direct references from one vault; scope that account to the
    exact vault and do not give the hosted runner access to Connect. Use one
    small Python command using the official Connect SDK for authenticated
    transport and raw item JSON for lossless reconciliation. The SDK's typed
    item model does not retain every supported field, including URL labels, so
    it must not be used for item round-trips:

    1. Select the vault by exact configured ID or name.
    2. Search by the stable item-key suffix and update the display title.
    3. Fail if more than one item matches.
    4. Retrieve the existing item JSON into process memory.
    5. Validate sections, field IDs, labels, and URL labels.
    6. Create missing items and empty manual placeholders.
    7. Update provider-backed and generated values owned by OpenTofu.
    8. Preserve populated manual placeholders and unknown fields.
    9. Delete removed OpenTofu-owned fields and URLs.
    10. Delete removed placeholders only while they remain empty.
    11. Write ownership metadata and native URLs through the Connect item API.
    12. Return only selected consumed fields, item IDs, and references.

    Keep this as one small purpose-built command, not a general framework. Pass
    reconciliation JSON through a sensitive environment value and inventory
    queries through stdin so secrets do not appear in process arguments or logs.

18. **Use two explicit credential flows.**

    Application-owned secret:

    ```text
    Declarative recipe
        -> reconciler generates in memory
        -> stored in 1Password
        -> deployment resolves op:// reference
    ```

    Examples:

    - Session secrets.
    - Application passwords.
    - Monitoring tokens.
    - Webhook secrets.
    - Database passwords controlled by the application deployment.

    Provider-issued credential:

    ```text
    OpenTofu/provider creates resource
        -> secret exists in encrypted target state
        -> post-apply sync writes it to 1Password
        -> deployment consumes 1Password copy
    ```

    Examples:

    - B2 application keys.
    - Resend API keys.
    - Pocket ID client secrets.
    - Tailscale auth keys.
    - Cloudflare tunnel or scoped API tokens.

    If provider-issued secret synchronization fails:

    - Stop deployment.
    - Do not recreate the provider resource automatically.
    - Retry synchronization from the sensitive state output.
    - Continue only after the exact value exists in 1Password.

19. **Detach existing 1Password items without deleting them.**

    Migration order:

    1. Field labels are normalized to their stable names.
    2. Update target deployments to stable references.
    3. Verify all consumers.
    4. Use `removed` blocks with `lifecycle.destroy = false` for managed 1Password resources where possible.
    5. Remove the corresponding data sources and REST resources from state.
    6. Remove the custom stateful module only after a no-change plan confirms no item deletion.

    Historical HCP and GCS generations will still contain the old item response data. Keep them narrowly access-controlled and let their retention windows expire. Client-side encryption remains deferred.

20. **Convert generated deployment repositories into authoritative source repositories.**

    Status: the `homelab-fly` source cutover is complete. Core retains repository
    governance and publishes one non-secret config variable, but owns no Fly
    repository files or Fly deployment-encryption credentials. The target
    repository owns reusable service implementations and templates, renders
    selected instances from the config during the job, resolves direct
    1Password references with a Services-vault read-only service account, and
    has completed the config-driven deployment successfully.

    Generated deployment workspaces belong under an ignored `.render/`
    directory. Shared tooling copies the selected service source there and
    renders every service-local `*.tmpl` to the same relative path without the
    suffix. Do not add generated template counterparts to `.gitignore` one by
    one or commit them. Docker and TrueNAS publish target-specific OCI packages
    from this ephemeral workspace; Fly deploys directly from it.

    Today `github.tf` and the service modules write repository files through `github_repository_file` and `modules/github_file_encrypted`.

    Repository-level tooling must remain generic, as it is in `homelab`:

    - `mise` tasks, shared workflows, repository configuration, and root documentation describe the platform and discover deployments from the repository layout.
    - Do not hard-code a service name or service-specific path in repository-level tooling.
    - Keep service-specific behavior in its data and template directories.
    - Adding a service should require adding its source files, not editing shared tooling.

    For each target repository:

    - Preserve the existing private repository.
    - Create a normal branch containing its current deployment files.
    - Move its platform-specific service YAML and templates into that repository.
    - Move its actual deployment workflow there.
    - Add a local `mise.toml`.
    - Add its own checks and schemas.
    - Enable Renovate normally.
    - Stop describing it as generated output.
    - Keep core ownership only for repository settings and protections.

    Recommended layout:

    ```text
    .github/workflows/
      check.yaml
      deploy.yaml

    templates/
      app.json.tmpl
      compose.json.tmpl
      services/<service>/

    .render/                 # ignored
      <target>/
        <service>/           # OCI package root after selecting one target
    mise.toml
    README.md
    ```

21. **Cut target repositories over one at a time.**

    Recommended order:

    1. `homelab-fly`
    2. `homelab-docker`
    3. `homelab-truenas`
    4. `homelab-workflows`

    For each repository:

    1. Copy platform source and templates without changing rendered behavior.
    2. Run the old and new renderers in shadow mode.
    3. Compare normalized outputs.
    4. Select one low-risk deployment.
    5. Deploy it through the target repository.
    6. Verify health and rollback.
    7. Move the remaining deployments.
    8. Disable the corresponding generator in core.
    9. Detach GitHub file resources with `destroy = false`.
    10. Confirm a core plan does not delete repository files.
    11. Remove the obsolete generation code only afterward.

22. **Use platform-native deployment mechanisms.**

    Fly:

    - Keep Dockerfiles and service-local deployment templates in `homelab-fly`.
    - Discover deployment instances from the non-secret config, not directory names or 1Password items.
    - Render `fly.toml`, certificates, scaling configuration, and application configuration during the selected deployment job.
    - Resolve secrets from 1Password during the job.
    - Use `fly secrets set` or `fly secrets import`.
    - Use `flyctl deploy`.
    - Require an explicit workflow input for deletion; never infer app deletion solely from a removed directory.
    - Keep one small Python lifecycle command for selection, rendering, deployment, and deletion; call `flyctl`, Gomplate, and `op` directly without shell wrappers.

    Docker/doco-cd:

    - Keep Compose definitions and service-local templates under `templates/services/<service>/` in `homelab-docker`, even when a similar TrueNAS template exists.
    - Discover deployment instances from the repository-specific non-secret config.
    - Render into an ignored target-specific workspace and never commit generated deployment output.
    - Resolve 1Password references only in GitHub Actions and stream every generated Compose, environment, certificate, and sidecar file directly into SOPS.
    - Keep only the minimal root and service `.doco-cd.yaml` discovery metadata plaintext.
    - Package each target as an OCI image with the strict `doco.v1` layout and publish immutable commit and moving `main` tags to GHCR.
    - Put rendered services directly at the OCI artifact root (`/<service>/`); the package name already identifies the target, so do not add `deployments/` or `<target>/` path layers. Reject duplicate instances of one service on the same target rather than silently overwriting a directory.
    - Let doco-cd poll the target-specific OCI package instead of cloning the source repository.
    - Give doco-cd only its target age private key; do not give it a 1Password token.
    - Keep the package private and mount a standard Docker config containing one shared classic GitHub PAT limited to `read:packages`; pass it through the sensitive `homelab_packages_token` root variable.
    - Let doco-cd use its native SOPS support when reading encrypted deployment files.
    - The doco-cd agent accesses its local Docker socket.
    - GitHub runners do not access that socket locally or across networks.
    - Use one repository-generic renderer for discovery, Gomplate rendering, encryption, and doco-cd metadata.
    - Delete services automatically through doco-cd auto-discovery when they disappear from the published desired-state package.
    - Preserve volumes on service removal unless an explicit destructive input is approved.
    - Treat doco-cd OCI support as experimental: keep the previous Git-based deployment revision recoverable until OCI polling, update, deletion, and rollback are verified.

    Status: the `homelab-docker` source cutover is implemented and pushed. The
    initial private package publication and layer audit pass: the package has
    the expected root service layout, all deployment payloads are encrypted for
    the target recipient, and only Doco discovery metadata is plaintext. The
    package remains private by policy. Doco polling uses standard registry
    authentication, so the core cutover no longer depends on public package
    visibility.

    TrueNAS:

    - Keep app templates, Compose templates, and sidecars under `templates/services/<service>/` in `homelab-truenas`; keep shared templates directly under `templates/`.
    - Render every target deployment on a hosted runner, resolve 1Password there, and SOPS-encrypt every file for the target age recipient.
    - Publish one complete target-specific OCI package with immutable commit and moving `main` tags instead of uploading normal GitHub Actions artifacts.
    - Put rendered services directly at the OCI artifact root (`/<service>/`); do not repeat the target or add a `deployments/` directory inside the target-specific package (`/redlib/`, `/aiometadata/`, and so on).
    - Run deployment on the target-local runner.
    - Pull the immutable OCI package identified by the workflow commit, then decrypt only the selected deployment in a temporary directory.
    - Reach TrueNAS through its supported API rather than Docker.
    - Clean the workspace after the API call.
    - Keep selection, hosted rendering, and target deployment as separate small scripts matching their trust boundaries; deployment and deletion remain one lifecycle command.
    - Retain target-specific Python only where structured TrueNAS API reconciliation and sidecar copying genuinely need it.

    Status: the `homelab-truenas` source cutover is implemented and pushed. Its
    private target package renders and publishes successfully, and the
    target-local runner reconciles it through the supported TrueNAS API.

    Workflows:

    - Keep maintenance workflows and their reviewed configuration in
      `homelab-workflows`.
    - Keep the repository independent of deployment configuration and secrets.
    - Use only the minimal shared mise, Prek, actionlint, Prettier, and Renovate
      tooling needed by its authored files.

    Status: the `homelab-workflows` source cutover is complete. The repository
    owns its workflow, configuration, checks, and maintenance tooling. Core
    retains repository governance but no longer generates or manages its files.

    OCI visibility and publication:

    - Keep OCI packages private.
    - Repository and GHCR package visibility are independent; do not assume a public repository makes a package public.
    - Make source repositories public only after their history, Actions logs, variables, templates, and workflows pass the same audit.
    - Give edge consumers only the narrow registry access they need: Doco uses a classic PAT with `read:packages`; TrueNAS uses the workflow's short-lived `GITHUB_TOKEN` with `packages: read`.
    - Do not give edge consumers a 1Password service-account token.

23. **Split multi-target services by expanded deployment identity.**

    A service deployed to two targets becomes two independently owned instances:

    ```text
    openspeedtest-au-hsp
    openspeedtest-au-truenas
    ```

    Move each platform-specific template to its owner:

    - Docker Compose template to `homelab-docker`.
    - TrueNAS catalog/app template to `homelab-truenas`.

    Do not create cross-repository template inheritance for a few shared scalar values. Use small target defaults locally. A little explicit repetition is safer and simpler than a shared templating framework.

24. **Preserve global Homepage, Gatus, and Traefik aggregation through a small nonsecret contract.**

    Use this as the general rendering boundary:

    - A normal service renders entirely from data and templates in its owning target repository.
    - An aggregator such as Homepage, Gatus, or Traefik may consume a shared, explicitly projected non-secret config because it needs cross-service context.
    - Never give an aggregator full remote-state access or the complete runtime service model.
    - The config contains only stable identity, target, display metadata, URLs or hosts, required feature flags, and programmatic secret references.
    - Keep credentials in 1Password and resolve them only in the consuming deployment job.
    - Publish the config independently of repository files so OpenTofu does not generate or commit target repository contents.
    - Reuse one stable config shape where practical; each aggregator projects only the fields it needs.

    Versioned configs are keyed and projected by target repository, then
    published as that repository's non-secret `CONFIG` GitHub Actions
    variable. The Fly config contains only Fly deployment instances and the
    monitored service fields consumed by Gatus. Do not publish one complete
    global config to every target. Each config must remain below the GitHub
    variable size limit, and publication must fail if a referenced service
    lacks a 1Password item. A per-repository config-hash trigger dispatches
    the target deployment workflow after the variable update; changing a
    variable without dispatching its deployment is incomplete.

    Service-local secret templates derive environment-variable names and
    `op://` references from the config. Do not commit enumerated item IDs or
    monitored-service secret lists. Derived fields such as `monitoring_basic`
    are reconciled in 1Password from their source token so rotation cannot
    leave the derived value stale.

    Shared external-provider metadata belongs in `data/config.yaml`. Homepage
    projects it into bookmarks and Gatus projects it into availability probes;
    neither aggregator reads the other service's data.

    Every target repository should expose the same minimal service-config fields in its YAML:

    ```text
    key
    title
    group
    target
    dashboard.enabled
    dashboard.icon
    monitoring.enabled
    monitoring.path
    urls.default.href
    ```

    Exclude:

    - Credentials.
    - Internal management IPs.
    - Docker socket information.
    - Provider IDs.
    - 1Password item bodies.

    Aggregation behavior:

    - Traefik consumes only its local target config.
    - Homepage may merge selected private target configs.
    - Gatus merges monitoring entries from all target configs.
    - Aggregator workflows check out the other private repositories read-only.
    - Duplicate service keys fail validation.
    - The deployed configuration records the consumed commit SHA of each source repository.
    - No aggregator reads another repository's OpenTofu state.
    - No aggregator discovers services by accessing remote Docker APIs.

25. **Create separate GCS state prefixes only after deployment ownership is stable.**

    Do not split state while target deployment code is still changing.

    For each new target state:

    - Use the same GCS bucket.
    - Use a dedicated prefix.
    - Keep client-side encryption deferred consistently across all state roots.
    - Use distinct GitHub concurrency groups.
    - Keep the same provider versions until the transfer is complete.

    If client-side encryption is resumed later, introduce it as a separate reviewed migration after the state split is stable.

26. **Build an address-by-address state transfer manifest.**

    Each entry must contain:

    ```text
    source address
    destination address
    remote object ID
    provider
    target repository
    import supported
    secret returned only at creation
    planned transfer method
    rollback method
    ```

    Classify every resource:

    - Importable stable resource: bucket, DNS record, repository, OIDC client where supported.
    - Secret-on-create resource: B2 key, Resend key, temporary auth token.
    - Generated local material: random passwords, TLS keys, age keys.
    - Generated repository file: stop managing rather than import.
    - Shared account-level resource: remain in core.

27. **Transfer importable resources without recreation.**

    Per target maintenance window:

    1. Freeze both source and destination applies.
    2. Back up both states securely.
    3. Add destination configuration and import blocks.
    4. Preview imports without applying.
    5. Record all remote object IDs.
    6. Remove exact source bindings using a reviewed `removed` block or exact `tofu state rm`.
    7. Do not destroy the remote object.
    8. Immediately apply the destination import plan.
    9. Run a source plan and require no destroy/create.
    10. Run a destination plan and require no change.
    11. Resume applies only after both pass.

    Use `moved` blocks for address changes within one state. They cannot transfer ownership between two active backends. OpenTofu recommends import or explicit state removal for moving an object between configurations. [OpenTofu moving resources](https://opentofu.org/docs/cli/state/move/) [OpenTofu imports](https://opentofu.org/docs/language/import/)

28. **Rotate secret-on-create resources instead of moving opaque state.**

    For B2, Resend, and similar keys:

    1. Create a new target-owned credential.
    2. Store it under the stable 1Password field.
    3. Deploy the application with the new credential.
    4. Verify application health.
    5. Revoke the old credential.
    6. Remove the old resource from core.
    7. Confirm the old key no longer authenticates.

    This is safer than copying secret-bearing state fragments or relying on incomplete import behavior.

29. **Remove the current overengineered machinery only after all cutovers.**

    Expected removals from the core repository:

    - `modules/github_file_encrypted`
    - Generated GitHub repository file resources
    - Generated deploy-request hash machinery
    - Generated workflow templates
    - Shared SOPS/age deployment encryption where 1Password references replace it
    - Stateful `modules/onepassword`
    - The OnePassword REST provider alias
    - Python decrypt/select scripts no longer needed by target repos
    - Debug render paths that exist solely for generated repositories
    - Targeted steady-state apply tasks such as `apply-services` and `apply-servers`

    Keep only:

    - Root-independent validation.
    - Shared infrastructure.
    - Stable model logic still used by core.
    - Provider-specific functionality with a real current consumer.
    - Target-local code in its owning repository.

30. **Use explicit validation gates after every phase.**

    GCS gate:

    - Native locking passes.
    - Object Versioning is enabled; the restore drill is deferred.
    - No public access.
    - Correct bucket region and lifecycle.
    - No credentials in backend configuration.

    Migration gate:

    - State addresses match.
    - Lineage is preserved.
    - Plan exit code is `0`.
    - HCP is read-only.
    - Secure backup exists.

    Deferred encryption gate, applicable only after encryption is explicitly resumed:

    - Raw current GCS object is ciphertext.
    - Missing passphrase causes a safe failure.
    - Correct passphrase reads state.
    - Unencrypted fallback is removed.
    - Offline key recovery is documented.

    1Password gate:

    - Existing item titles and IDs are preserved.
    - Parenthesized resource keys are unique within each vault.
    - Exact `snake_case` field names.
    - Duplicate items fail.
    - Existing values are preserved.
    - No application-owned generated value remains in OpenTofu state.
    - Full item response bodies are absent from new state.

    Target-repository gate:

    - Repository is authoritative, not generated.
    - Old and new rendered behavior matches.
    - Deployment rollback works.
    - No secret is committed.
    - No remote Docker access exists.
    - Core no longer proposes changes to target files.

    State-split gate:

    - Every transferred object appears in exactly one state.
    - Neither source nor destination proposes recreation.
    - Provider-issued credentials remain valid.
    - Both states pass a no-change plan.

31. **Keep rollback paths live until each phase proves itself.**

    - Backend migration: retain HCP.
    - Deferred encryption migration: if resumed, retain the unencrypted fallback temporarily and keep the offline passphrase.
    - 1Password migration: retain old fields as aliases until consumer validation completes.
    - Repository cutover: keep the old deploy workflow disabled but recoverable for one release cycle.
    - Target deployment: roll back to the previous Git commit, OCI digest, or Fly/TrueNAS deployment revision.
    - State split: retain access-controlled source and destination state backups until both roots pass no-change plans.
    - Credential rotation: retain the old credential until the new application health check passes.

32. **Defer optional improvements until the core plan is complete.**

    Later options:

    - Copy selected GCS generations to R2 under generation-specific keys if another backup tier becomes worthwhile.
    - Make target template repositories public only after their visibility audit; keep deployment packages private.
    - Replace GitHub with Forgejo/Woodpecker only if GitHub becomes an actual constraint.
    - Use separate GCS buckets or encryption keys per repository if stronger state isolation becomes necessary.
    - Replace the remaining target-specific Python only when a simpler supported platform tool exists.

    None of these belongs in the HCP-to-GCS migration.

33. **Define completion narrowly.**

    The simplification is complete when:

    - HCP is gone.
    - GCS locking and versioning are tested; the restore drill remains outside the current completion criteria.
    - Client-side state and plan encryption remains explicitly outside the current completion criteria.
    - Source repository visibility matches the verified exposure policy and OCI packages remain private.
    - Target repositories own their service source, templates, deployment, and service-scoped resources.
    - Core no longer generates target repository contents.
    - Application-owned secrets originate in and remain in 1Password.
    - Provider-issued credentials are mirrored to 1Password through a controlled post-apply path.
    - 1Password titles, sections, fields, URLs, and tags follow one stable schema.
    - No cross-network Docker access exists.
    - Homepage, Gatus, and Traefik still receive the data they need.
    - B2, Resend, OIDC, Fly, TrueNAS, Docker/doco-cd, and other live features remain supported.
    - Every state root produces a reviewed no-change plan.
    - `mise run check` and `mise run prek` pass in every affected repository.

The Terrashark failure-mode review drives the strict separation between backend migration, secret migration, repository ownership, and cross-state transfer. Client-side encryption remains documented but deferred until explicitly resumed.
