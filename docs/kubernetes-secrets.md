# Kubernetes Secret Roots

Cluster credentials live in a dedicated 1Password vault per cluster:
`Kubernetes: mbk` and `Kubernetes: syd`. Each vault is the isolation boundary
for its cluster's service account — a credential leak on one cluster cannot
read the other's secrets. OpenTofu delivers the Tailscale operator OAuth
clients, Cloudflare tunnel tokens, ACME DNS tokens, and administrator
kubeconfigs into these vaults. The External Secrets bootstrap credential is
maintained manually and is the cluster's secret root of trust: every other
workload secret is reconciled from it.

## Item naming

The External Secrets `onepasswordSDK` provider prepends `op://<vault>/` to
each `remoteRef.key`, so every key must read `<item-title>/<field>`, and the
SDK reference syntax allows only `[a-zA-Z0-9._-]` in item titles. Items in the
Kubernetes vaults therefore use hyphenated, cluster-suffixed titles:

```text
<service>-<cluster>
```

For example `cloudflare-acme-mbk` or `pocket-id-mbk`, addressable as
`op://Kubernetes: mbk/<service>-<cluster>/<field>`. OpenTofu owns the
delivered titles; rename them through configuration, never in 1Password, or
the next apply reverts the manual edit. Operator-facing items in the Homelab
vault keep the `<Credential type>: <scope>` style because External Secrets
never references them.

## Items

| Item                                  | Owner    | Contents                         |
| ------------------------------------- | -------- | -------------------------------- |
| `cloudflare-acme-mbk`                 | OpenTofu | Cloudflare DNS API token         |
| `cloudflare-tunnel-mbk`               | OpenTofu | Tunnel ID and token              |
| `kubeconfig-mbk`                      | OpenTofu | Cluster administrator kubeconfig |
| `tailscale-operator-mbk`              | OpenTofu | OAuth client ID and secret       |
| `Service Account Auth Token: mbk-eso` | Manual   | 1Password service-account token  |

The manual item predates this convention. Rename it to a hyphenated,
cluster-suffixed title before External Secrets references it by key.

Create the manual item as an API Credential so the token is addressable as
`op://Kubernetes: mbk/<item-title>/credential`. Scope the service account to
the `Kubernetes: mbk` vault with read and write access.

## Bootstrap injection

Inject the service-account token into the cluster as a Kubernetes Secret
before the External Secrets controller first starts:

```sh
kubectl -n external-secrets create secret generic onepassword-bootstrap \
  --from-literal=token="$(op read 'op://Kubernetes: mbk/Service Account Auth Token: mbk-eso/credential')" \
  --dry-run=client -o yaml | kubectl apply -f -
```

The namespace, secret name, and key are the contract that the `kubelab`
ClusterSecretStore references. `kubelab` owns the binding, not this
repository.

## Re-injection

After rebuilding the cluster or reinstalling the controller, run the same
injection command again. It is idempotent and overwrites any previous token.

## Rotation

1. Regenerate the service-account token in 1Password and save the item.
2. Re-run the injection command to update the Kubernetes Secret.
3. Restart the controller if it caches credentials:

   ```sh
   kubectl -n external-secrets rollout restart deployment/external-secrets
   ```

4. Verify an ExternalSecret reconciles and delete any stale secrets.

## Safety

- Never commit the token, secret manifests, or rendered output to Git.
- Keep each service account scoped to its own cluster vault only.
- Create the `Kubernetes: syd` vault and service account only when the Sydney
  rollout gate opens; until then the vault may stay empty.
- Test rotation before relying on it for recovery.
