# Dashboard

Homepage data is generated from server and service dashboard cards.

## Server Cards

When a server has `networking.management_port` and `dashboard` is null, a
default dashboard card is generated from the server identity, type icon,
management URL, and group.

Set `dashboard: []` to suppress cards. Set explicit `dashboard` cards to take
full control.

## Service Cards

Service dashboard cards are rendered through `templatestring()` with the normal
service template context. Cards with an empty `name` are ignored.

The Homepage service itself is excluded from generated service cards.

## Sorting & Layout

Cards with widgets sort before cards without widgets. Cards then sort by lower
case name, source key, and card index.

Groups that match server identity groups are placed on the `Servers` tab. Other
groups are placed on the `Services` tab. A `Providers` group is inserted between
service groups and server groups.

Homepage layout defaults to two columns and row style. The Homepage service can
override service-group layout through `service.data.groups`.

## URLs In 1Password

Service dashboard links that are not already present in `service.urls` are added
to the matching 1Password item as additional URLs.
