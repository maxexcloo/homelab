# Services

Services are declared in `data/services/*.yaml`. Explicit targets and servers
selected by `target_feature` each produce an expanded service instance.

Expanded service keys use `<service>-<target>`, for example
`immich-au-truenas`. Target-level `credentials`, `data`, `features`, `fly`, and
`truenas` values deep-merge over service-level values.

`target_feature` adds every server with the matching feature flag as a target.
Explicit `targets` entries are merged on top, so they can override automatic
targets.

## Data

Service YAML can include a root `data` value with any JSON-compatible shape.
Templates receive the rendered value as `service.data`.

Targets can set `targets.<key>.data`. Object values deep-merge with target
values winning; scalars, arrays, and null replace the service-level value.

## Templates

Templates receive:

- `defaults` - merged global config and defaults
- `server` - the rendered target server with runtime values, or null for
  non-server targets
- `servers` - all rendered servers with runtime values
- `service` - the current expanded service
- `services` - all expanded services plus declared import aliases

`data`, `dashboard`, and `truenas` values are rendered with `templatestring()`
before file templates run. Adjacent services are exposed without runtime
credentials unless they are explicitly imported.

## Deployment

See `docs/deployments.md` for platform deployment behaviour and
`docs/routing.md` for URL, DNS, label, and container behaviour.

## Files

Templates live in the repository that owns the target platform. This repository
publishes only the modeled deployment context through its `CONFIG` output.
