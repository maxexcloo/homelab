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

Non-empty `data.shared` objects are also published generically to every
deployment as `services.<expanded-service-key>.data`. This shares deliberate,
non-secret service data across templates without adding service-specific HCL.
When present, `data.shared` must be an object.

Targets can set `targets.<key>.data`. Object values deep-merge with target
values winning; scalars, arrays, and null replace the service-level value.

## Templates

Templates receive:

- `defaults` - merged global config and defaults
- `server` - the rendered target server with runtime values, or null for
  non-server targets
- `servers` - all deterministic server models; the target and explicitly
  imported aliases include their rendered runtime values
- `service` - the current expanded service
- `services` - all deterministic expanded service models; explicitly imported
  aliases include their runtime values

`data`, `dashboard`, and `truenas` values are rendered with `templatestring()`
before file templates run. Adjacent services are exposed without runtime
credentials unless they are explicitly imported.

Template expressions use HCL syntax inside `${...}` and must produce values
convertible to strings. Use `jsonencode()` explicitly when a consumer needs
structured JSON inside a string. Rendering is a single pass, so an expression
must not depend on another templated value being expanded first.

## Deployment

See `docs/deployments.md` for platform deployment behaviour and
`docs/routing.md` for URL, DNS, label, and container behaviour.

## Files

Templates live in the repository that owns the target platform. This repository
publishes only the modelled deployment context through each target repository's
GitHub Actions `CONFIG` variable.
