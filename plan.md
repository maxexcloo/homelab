# Homelab Simplification Plan

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
   - Backend migration, state encryption, secret refactoring, repository splitting, and state splitting happen in separate phases.

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

6. **Prepare a dedicated 1Password item for state encryption.**

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

7. **Make the OpenTofu version requirement match the encryption requirement.**

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

12. **Enable OpenTofu client-side encryption in a separate phase.**

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

13. **Perform an encrypted restore drill.**

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

    The existing `.github/workflows/prek.yml` should continue to:

    - Run on GitHub-hosted runners.
    - Use `tofu init -backend=false`.
    - Run formatting, schema validation, linting, and static checks.
    - Have no GCP identity.
    - Have no 1Password Connect token.
    - Have no provider credentials.
    - Have no self-hosted runner access.

    This lets pull requests validate untrusted changes without exposing infrastructure access.

15. **Add a separate protected delivery workflow after GCS is stable.**

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

    Existing item titles such as `Beszel (beszel-au-truenas)` should migrate to exact stable resource keys:

    ```text
    beszel-au-truenas
    au-truenas
    opentofu-state-homelab
    ```

    Use the existing vault separation:

    - `Servers`
    - `Services`
    - Add `Automation`

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
    Item: beszel-au-truenas

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

    Tags should also be deterministic:

    ```text
    homelab/managed
    service/beszel
    target/truenas
    ```

17. **Move 1Password reconciliation outside OpenTofu.**

    The current `modules/onepassword` reads complete item responses through `data.http.item`. Those response bodies can persist credential values in state.

    Replace that lifecycle with one thin reconciler using the official `op` CLI and Connect:

    1. Select the vault by exact configured ID or name.
    2. Search for the exact stable item title.
    3. Fail if more than one item matches.
    4. Retrieve the existing item JSON into process memory.
    5. Validate sections, field IDs, labels, and URL labels.
    6. Generate only missing application-owned secrets.
    7. Preserve every existing nonempty value.
    8. Never rotate without an explicit rotation flag.
    9. Update native URLs and managed metadata.
    10. Warn about unknown fields; do not delete them automatically.
    11. Write through `op item create` or `op item edit`.
    12. Return only item IDs and `op://` references, never values.

    Keep this as one small purpose-built command, not a general framework. Use JSON stdin/stdout between `op` and the reconciler so secrets do not appear in process arguments or logs.

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

    1. Add stable metadata to existing items.
    2. Match old human-readable titles to stable resource keys.
    3. Rename items once.
    4. Rename field labels from `_ro`/`_rw` to their stable names.
    5. Keep temporary alias fields if any deployment still uses the old reference.
    6. Update deployments to new references.
    7. Verify all consumers.
    8. Use `removed` blocks with `lifecycle.destroy = false` for managed 1Password resources where possible.
    9. Remove the corresponding data sources and REST resources from state.
    10. Remove the custom stateful module only after a no-change plan confirms no item deletion.

    Historical HCP and early GCS generations will still contain the old item response data. Keep them access-controlled, client-encrypt new GCS generations, and let their retention windows expire.

20. **Convert generated deployment repositories into authoritative source repositories.**

    Today `github.tf` and the service modules write repository files through `github_repository_file` and `modules/github_file_encrypted`.

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
      check.yml
      deploy.yml

    data/
      defaults.yml
      services/*.yml

    templates/
      services/<service>/

    scripts/
      only target-specific code

    backend.tf
    encryption.tf
    main.tf
    outputs.tf
    providers.tf
    terraform.tf
    variables.tf
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

    - Keep `fly.toml`, Dockerfiles, and service templates in `homelab-fly`.
    - Resolve secrets from 1Password during the job.
    - Use `fly secrets set` or `fly secrets import`.
    - Use `flyctl deploy`.
    - Require an explicit workflow input for deletion; never infer app deletion solely from a removed directory.
    - Python should not be required for normal Fly deployment.

    Docker/doco-cd:

    - Keep Compose definitions in `homelab-docker`.
    - Use doco-cd's native Git/OCI and 1Password Connect support.
    - Store `op://` references or doco-cd external-secret declarations, not rendered values.
    - The doco-cd agent accesses its local Docker socket.
    - GitHub runners do not access that socket locally or across networks.
    - Preserve volumes on service removal unless an explicit destructive input is approved.

    TrueNAS:

    - Keep app templates, Compose templates, and sidecars in `homelab-truenas`.
    - Run deployment on the target-local runner.
    - Reach TrueNAS through its supported API rather than Docker.
    - Resolve 1Password values into a protected temporary workspace.
    - Clean the workspace after the API call.
    - Retain a small target-specific Python command only where structured TrueNAS API reconciliation and sidecar copying genuinely need it.
    - Consolidate the existing selection, deploy, delete, and decrypt scripts rather than creating a general deployment framework.

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

    Every target repository should expose the same minimal service-catalog fields in its YAML:

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

    - Traefik consumes only its local target catalog.
    - Homepage may merge selected private target catalogs.
    - Gatus merges monitoring entries from all target catalogs.
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
    - Use the same encryption configuration and 1Password recovery key initially.
    - Use distinct GitHub concurrency groups.
    - Keep the same provider versions until the transfer is complete.

    Later, separate encryption keys per state can be introduced with OpenTofu fallback-based key rotation if the extra isolation is worthwhile.

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
    - Version restore passes.
    - No public access.
    - Correct bucket region and lifecycle.
    - No credentials in backend configuration.

    Migration gate:

    - State addresses match.
    - Lineage is preserved.
    - Plan exit code is `0`.
    - HCP is read-only.
    - Secure backup exists.

    Encryption gate:

    - Raw current GCS object is ciphertext.
    - Missing passphrase causes a safe failure.
    - Correct passphrase reads state.
    - Unencrypted fallback is removed.
    - Offline key recovery is documented.

    1Password gate:

    - Exact stable item titles.
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
    - Encryption migration: retain the unencrypted fallback temporarily and keep the offline passphrase.
    - 1Password migration: retain old fields as aliases until consumer validation completes.
    - Repository cutover: keep the old deploy workflow disabled but recoverable for one release cycle.
    - Target deployment: roll back to the previous Git commit or Fly/TrueNAS deployment revision.
    - State split: retain encrypted source and destination state backups until both roots pass no-change plans.
    - Credential rotation: retain the old credential until the new application health check passes.

32. **Defer optional improvements until the core plan is complete.**

    Later options:

    - Copy each raw encrypted GCS generation to R2 under a generation-specific key.
    - Make target template repositories public after separating topology and deployment data.
    - Replace GitHub with Forgejo/Woodpecker only if GitHub becomes an actual constraint.
    - Use separate GCS buckets or encryption keys per repository if stronger state isolation becomes necessary.
    - Replace the remaining target-specific Python only when a simpler supported platform tool exists.

    None of these belongs in the HCP-to-GCS migration.

33. **Define completion narrowly.**

    The simplification is complete when:

    - HCP is gone.
    - GCS locking, versioning, restore, and encryption are tested.
    - Current repositories remain private.
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

The Terrashark failure-mode review drives the strict separation between backend migration, encryption, secret migration, repository ownership, and cross-state transfer; combining those phases would make rollback and identity verification unreliable.
