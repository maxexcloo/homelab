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

TrueNAS publishes one self-contained context per deployment. The same context is
fingerprinted for change selection and passed unchanged to its platform template.

Service-wide generated settings are attached to the deployment that consumes
them under `deployment.custom.<service>`. Dozzle, Gatus, Homepage, and Traefik
therefore remain root-owned configuration and can move between Docker, Fly, and
TrueNAS without moving their aggregation logic into a platform repository.

Gatus and Homepage are optional singleton aggregators. When present, Gatus must
enable the `mail` and `tailscale` features and provide a `data.endpoints` list.

Docker publishes encrypted OCI packages for doco-cd. Fly deploys from a hosted
runner.
TrueNAS publishes encrypted OCI packages on a hosted runner and decrypts them
only on the matching TrueNAS runner.

Deployment packages remain private. Source repositories may become public after
their templates, workflows, history, logs, and variables pass a visibility
audit.
