# Backend State & Recovery

The root uses the externally bootstrapped `homelab-opentofu` Google Cloud
Storage bucket, prefix `homelab`, and default workspace. The root must never
manage the bucket that stores its active state.

The last read-only backend review on 15 August 2026 confirmed object versioning,
uniform bucket-level access, and public-access prevention. It also confirmed
that retention and soft-delete protection were not enabled and that legacy
bucket and object IAM roles remained. Review those accepted risks before
broadening state access.

The archived `states/core` prefix is stale historical evidence. Never migrate
it into `homelab`, apply the archived branch against it, or delete its objects as
part of a routine substrate change.

Treat every state reader as a secret reader. State contains generated Talos,
Tailscale, Cloudflare, and other credentials even when plan output is redacted.
Keep state, plans, backups, and recovery material outside Git and restrict them
to the operator performing the recovery.

## Recovery

1. Freeze plans and applies for this root.
2. Record the affected GCS object generation, OpenTofu version, workspace, and
   operator.
3. Copy the current and selected historical object generations to secure
   storage outside the repository.
4. Restore the selected generation in GCS without changing the backend prefix.
5. Compare `tofu state list` before and after restoration.
6. Run a refresh-only plan, review every change, and obtain explicit approval
   before any corrective apply.

Never use `tofu init -migrate-state` for recovery. Before `tofu force-unlock`,
verify the lock holder, process, and timestamp and prove that no apply is still
running.
