# 1Password Adoption

The `Servers` vault owns retained-machine access and Talos recovery/bootstrap
items. The logical `kubernetes` vault currently maps to the existing `Services`
vault and owns administrator kubeconfigs, Tailscale operator credentials, and
Cloudflare tunnel credentials. This keeps the current 1Password Connect token
usable without hard-coding a vault UUID.

Before changing the logical mapping to a dedicated `Kubernetes` vault,
inventory the existing item UUIDs and titles. Grant the 1Password Connect
account access to that vault, move existing cluster items manually where
required, then import or reconcile their exact resource addresses through
`migrations.tf`. Do not let `prevent_destroy` be bypassed to replace a recovery
item, and do not create a duplicate item merely to avoid adoption.

The 1Password Connect account must have only the vault permissions required by
these resources. The separate Kubernetes service-account roots used by
External Secrets remain manual bootstrap credentials and are not created by
this OpenTofu root.
