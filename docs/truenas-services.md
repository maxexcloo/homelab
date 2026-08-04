# TrueNAS Services

TrueNAS service templates live in the TrueNAS deployment repository under
`services/<service>/`.

- Use `app.json.tmpl` for a catalog app or `compose.yaml.tmpl` for a custom app.
- Put sidecars beside the app template; `.tmpl` is removed after rendering.
- Keep service data, target overrides, relationships, and non-secret computed
  values in this repository's YAML model.
- Use programmatic `op://` references from `CONFIG`; never embed credentials in a
  template or repository variable.
- Keep sidecar destinations on writable app-managed storage.

The hosted workflow renders and encrypts every file. The TrueNAS runner decrypts
the artifact, updates or creates the app, writes sidecars through mounted
containers, and redeploys when sidecars are present.

Before changing a catalog app, check the current upstream TrueNAS catalog schema
for its value and storage keys.
