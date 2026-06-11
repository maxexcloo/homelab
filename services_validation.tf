locals {
  # Cloudflare Universal SSL covers only one subdomain level.
  _services_validation_cloudflare_deep_subdomains = [
    for record_key, record in local.dns_render_records_services : "${record_key} (${record.name})"
    if(
      try(record.proxied, false) &&
      length(split(".", record.name)) - length(split(".", record.zone)) > 1
    )
  ]

  _services_validation_cloudflared_missing = flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.urls : "${service_key} -> ${route.host}"
      if(
        route.expose == "cloudflare" &&
        try(local.servers_model[service.target], null) != null &&
        !local.servers_model[service.target].features.cloudflared
      )
    ]
  ])

  _services_validation_file_key_mismatches = [
    for service_key, service in local.services_input : "${service_key} -> ${service.identity.name}"
    if service_key != service.identity.name
  ]

  _services_validation_fly_ports_missing = [
    for service_key, service in local.services_input : service_key
    if(
      try(service.targets.fly, null) != null &&
      service.routing.backend_port == null
    )
  ]

  _services_validation_homepage_missing = length([
    for service_key, service in local.services_input : service_key
    if service.identity.name == "homepage"
  ]) == 0

  _services_validation_import_alias_conflicts = flatten([
    for service_key, imports in local.services_model_imports : [
      for import_alias, service_ref in imports : "${service_key}.${import_alias} -> ${service_ref}"
      if try(local.services_model[import_alias], null) != null
    ]
  ])

  _services_validation_invalid_imports = flatten([
    for service_key, imports in local.services_model_imports : [
      for import_alias, service_ref in imports : "${service_key}.${import_alias} -> ${service_ref}"
      if try(local.services_model[service_ref], null) == null
    ]
  ])

  _services_validation_invalid_targets = flatten([
    for service_key, service in local.services_input : [
      for target in keys(service.targets) : "${service_key} -> ${target}"
      if(
        target != "fly" &&
        try(local.servers_model[target], null) == null
      )
    ]
  ])

  _services_validation_proxy_no_port = flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.urls : "${service_key} -> ${route.host}"
      if(
        startswith(route.expose, "proxy-") &&
        route.backend_port == null
      )
    ]
  ])

  _services_validation_proxy_server_missing = flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.urls : "${service_key} -> ${route.proxy_server}"
      if(
        route.proxy_server != null &&
        try(local.servers_model[route.proxy_server], null) == null
      )
    ]
  ])

  _services_validation_routes_not_unique = [
    for service_key, service in local.services_model : service_key
    if length(compact([for route in service.routing.urls : route.host])) != length(distinct(compact([for route in service.routing.urls : route.host])))
  ]

  _services_validation_server_routes_missing_traefik = flatten([
    for server_key, server in local.servers_model : [
      for route in server.routing.urls : "${server_key}.${route.url} -> ${startswith(route.expose, "proxy-") ? trimprefix(route.expose, "proxy-") : server_key}"
      if(
        route.expose != "cloudflare" &&
        length([
          for service in values(local.services_model) : service
          if(
            service.identity.name == "traefik" &&
            service.target == (startswith(route.expose, "proxy-") ? trimprefix(route.expose, "proxy-") : server_key)
          )
        ]) == 0
      )
    ]
  ])

  _services_validation_target_credentials_invalid = [
    for service_key, service in local.services_model : service_key
    if(
      service.credentials.source == "target" &&
      try(!local.servers_model[service.target].features.password, true)
    )
  ]

  _services_validation_target_credentials_password_feature = [
    for service_key, service in local.services_model : service_key
    if(
      service.credentials.source == "target" &&
      service.features.password
    )
  ]

  _services_validation_truenas_config_invalid_targets = [
    for service_key, service in local.services_model : service_key
    if(
      try(local.truenas_input_servers[service.target], null) == null &&
      (
        service.truenas.catalog_app != "" ||
        length(service.truenas.env) > 0 ||
        service.truenas.port_key != local.defaults.targets.truenas.port_key ||
        service.truenas.train != local.defaults.targets.truenas.train
      )
    )
  ]

  _services_validation_truenas_missing_template = [
    for service_key, service in local.truenas_input_services : service_key
    if(
      try(local.services_render_write_compose[service_key], null) == null &&
      try(local.truenas_prepare_catalog_templates[service_key], null) == null
    )
  ]

  _services_validation_unmanaged_urls = flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.urls : "${service_key} -> ${route.url}"
      if(
        route.url != null &&
        service.target != "fly" &&
        route.expose != "cloudflare" &&
        route.https &&
        try(local.dns_render_managed_zones_by_url[route.url], null) == null
      )
    ]
  ])
}

resource "terraform_data" "services_validation" {
  input = keys(local.services_input)

  lifecycle {
    # Deep generated service hostnames need custom short URLs or dedicated certs.
    precondition {
      condition     = length(local._services_validation_cloudflare_deep_subdomains) == 0
      error_message = "Cloudflare-proxied hostnames exceed Universal SSL coverage (max one subdomain level): ${join(", ", nonsensitive(local._services_validation_cloudflare_deep_subdomains))}"
    }

    # Cloudflare-exposed server services need a tunnel on the target server.
    precondition {
      condition = length(local._services_validation_cloudflared_missing) == 0
      error_message = (
        "Cloudflare-exposed services deployed to servers require cloudflared on the target server: ${join(", ", local._services_validation_cloudflared_missing)}"
      )
    }

    precondition {
      condition = length(local._services_validation_file_key_mismatches) == 0
      error_message = (
        "Service YAML filenames must match identity.name: ${join(", ", local._services_validation_file_key_mismatches)}"
      )
    }

    precondition {
      condition     = length(local._services_validation_fly_ports_missing) == 0
      error_message = "Fly services must have routing.backend_port set: ${join(", ", nonsensitive(local._services_validation_fly_ports_missing))}"
    }

    precondition {
      condition     = !local._services_validation_homepage_missing
      error_message = "A service with identity.name = homepage is required for the dashboard to render"
    }

    precondition {
      condition = length(local._services_validation_import_alias_conflicts) == 0
      error_message = (
        "Service import aliases must not shadow real service keys: ${join(", ", local._services_validation_import_alias_conflicts)}"
      )
    }

    precondition {
      condition = length(local._services_validation_invalid_imports) == 0
      error_message = (
        "Invalid service imports found in services configuration: ${join(", ", local._services_validation_invalid_imports)}"
      )
    }

    precondition {
      condition = length(local._services_validation_invalid_targets) == 0
      error_message = (
        "Invalid server references found in services configuration: ${join(", ", local._services_validation_invalid_targets)}"
      )
    }

    precondition {
      condition     = length(local._services_validation_proxy_no_port) == 0
      error_message = "Proxy-exposed services must have routing.backend_port set: ${join(", ", local._services_validation_proxy_no_port)}"
    }

    precondition {
      condition     = length(local._services_validation_proxy_server_missing) == 0
      error_message = "Proxy-exposed services reference a non-existent server: ${join(", ", local._services_validation_proxy_server_missing)}"
    }

    precondition {
      condition     = length(local._services_validation_routes_not_unique) == 0
      error_message = "Service routing hostnames must be unique per target: ${join(", ", local._services_validation_routes_not_unique)}"
    }

    precondition {
      condition     = length(local._services_validation_server_routes_missing_traefik) == 0
      error_message = "Non-Cloudflare server routing requires a Traefik service target on the routing server: ${join(", ", local._services_validation_server_routes_missing_traefik)}"
    }

    precondition {
      condition = length(local._services_validation_target_credentials_invalid) == 0
      error_message = (
        "Service credentials.source = target requires a server target with password enabled: ${join(", ", local._services_validation_target_credentials_invalid)}"
      )
    }

    precondition {
      condition = length(local._services_validation_target_credentials_password_feature) == 0
      error_message = (
        "Service credentials.source = target cannot be combined with service features.password: ${join(", ", local._services_validation_target_credentials_password_feature)}"
      )
    }

    precondition {
      condition = length(local._services_validation_truenas_config_invalid_targets) == 0
      error_message = (
        "targets.<key>.truenas settings are only valid for services targeting TrueNAS servers: ${join(", ", local._services_validation_truenas_config_invalid_targets)}"
      )
    }

    # TrueNAS services need either a custom compose template or catalog template.
    precondition {
      condition     = length(local._services_validation_truenas_missing_template) == 0
      error_message = "TrueNAS catalog services require templates/services/{identity.service}/app.json.tftpl: ${join(", ", nonsensitive(local._services_validation_truenas_missing_template))}"
    }

    # HTTPS service URLs need managed DNS so ACME delegation can resolve.
    precondition {
      condition = length(local._services_validation_unmanaged_urls) == 0
      error_message = (
        "Service routing URLs must be in a managed DNS zone (data/dns/) for ACME delegation: ${join(", ", local._services_validation_unmanaged_urls)}"
      )
    }
  }
}
