# TrueNAS Services

TrueNAS service templates live in the TrueNAS deployment repository under
`<service>/`. Shared renderer templates live under `.github/templates/`.

- Use `app.json.tmpl` for a catalog app or `compose.yaml.tmpl` for a custom app.
- Put sidecars beside the app template; `.tmpl` is removed after rendering.
- Keep service data, target overrides, relationships, and non-secret computed
  values in this repository's YAML model.
- Use programmatic `op://` references from `CONFIG`; never embed credentials in a
  template or repository variable.
- Keep sidecar destinations on writable app-managed storage.

The hosted workflow renders and encrypts every file into a target-specific OCI
package. The TrueNAS runner pulls its immutable package revision, decrypts the
selected service, updates or creates the app, writes sidecars through mounted
containers, and redeploys when sidecars are present.

Before changing a catalog app, check the current upstream TrueNAS catalog schema
for its value and storage keys.
