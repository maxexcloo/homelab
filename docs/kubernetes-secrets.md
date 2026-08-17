# Kubernetes Secret Roots

Cluster credentials live in a dedicated 1Password vault per cluster:
`Kubernetes: mbk` and `Kubernetes: syd`. Each vault is the isolation boundary
for its cluster's service account — a credential leak on one cluster cannot
read the other's secrets. OpenTofu delivers the Tailscale operator OAuth
clients, Cloudflare tunnel tokens, ACME DNS tokens, and administrator
kubeconfigs into these vaults. The External Secrets bootstrap credential is
maintained manually and is the cluster's secret root of trust: every other
workload secret is reconciled from it.

Item names follow one convention: `<Credential type>: <scope>`, with the type
in Title Case and the scope a lowercase cluster key or FQDN.

## Items

| Item                                    | Owner    | Contents                         |
| --------------------------------------- | -------- | -------------------------------- |
| `External Secrets Service Account: mbk` | Manual   | 1Password service-account token  |
| `Tailscale Operator: mbk`               | OpenTofu | OAuth client ID and secret       |
| `Cloudflare Tunnel: mbk`                | OpenTofu | Tunnel ID and token              |
| `Cloudflare ACME DNS: mbk`              | OpenTofu | Cloudflare DNS API token         |
| `Kubeconfig: mbk`                       | OpenTofu | Cluster administrator kubeconfig |

Create the manual item as an API Credential so the token is addressable as
`op://Kubernetes: mbk/External Secrets Service Account: mbk/credential`.
Scope the service account to the `Kubernetes: mbk` vault with read and write
access.

## Bootstrap injection

Inject the service-account token into the cluster as a Kubernetes Secret
before the External Secrets controller first starts:

```sh
kubectl -n external-secrets create secret generic onepassword-bootstrap \
  --from-literal=token="$(op read 'op://Kubernetes: mbk/External Secrets Service Account: mbk/credential')" \
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
