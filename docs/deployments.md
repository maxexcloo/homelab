# Deployments

Each target repository owns its service templates, workflow, deployment logic,
and dependency updates. This repository owns infrastructure models and publishes
one non-secret `CONFIG` repository variable per target.

`CONFIG` contains stable deployment identities, non-secret runtime data, and
programmatic 1Password references. Large configs may be gzip-compressed and
base64-encoded to fit the GitHub Actions variable limit.

Target workflows select deployments from `CONFIG`, render their local templates,
and resolve credentials only where they are deployed. Changing `CONFIG` triggers
the target workflow automatically. Removing a deployment triggers its target's
delete action.

Docker renders encrypted files for doco-cd. Fly deploys from a hosted runner.
TrueNAS renders on a hosted runner, uploads a short-lived SOPS-encrypted artifact,
and decrypts it only on the matching TrueNAS runner.

Deployment repositories are private. They can become public only after their
templates, workflows, history, and generated artifacts are confirmed secret-free.
