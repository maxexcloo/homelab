# Backend State

The root uses workspace `default` at prefix `homelab` in the externally
bootstrapped `homelab-opentofu` GCS bucket. The move from the temporary
`states/homelab-kubernetes/au` prefix completed on 2026-08-15. The legacy
`states/core` objects were never migrated into this root and remain historical
evidence only.

`mise run init` deliberately uses `-backend=false` for validation. To connect a
trusted workstation to the active backend, first review `backend.tf` and the
selected Google identity, then initialise with:

```shell
tofu init -reconfigure -input=false
tofu workspace show
tofu state list
```

The expected workspace is `default`. Do not use `tofu init -migrate-state` for
this root and do not accept a plan that proposes recreating imported resources.
Plans and applies require explicit review and approval.

GCS object versioning is the state rollback mechanism. Before a state operation,
securely capture the current state and address inventory outside the repository.
Treat both as secret-bearing material, preserve the old object versions through
the rollback window, and never commit them.
