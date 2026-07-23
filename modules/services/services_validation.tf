locals {
  # Cloudflare Universal SSL covers only one subdomain level.
  _services_validation_cloudflare_deep_subdomains = flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.routes : "${service_key}-${route.id} (${route.host})"
      if(
        route.expose == "cloudflare" &&
        route.host != null &&
        route.zone != null &&
        length(split(".", route.host)) - length(split(".", route.zone)) > 1
      )
    ]
  ])

  _services_validation_cloudflared_missing = flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.routes : "${service_key}-${route.id} -> ${route.host}"
      if(
        route.expose == "cloudflare" &&
        service.target != "fly" &&
        !try(local.servers_model[service.target].features.cloudflared, false)
      )
    ]
  ])

  _services_validation_credential_names = {
    for service_key, service in local.services_input_targets : service_key => concat(
      keys(service.credentials.fields),
      flatten([
        for credential_name, generator in service.credentials.generated :
        generator.type == "x509" ? ["${credential_name}_certificate", "${credential_name}_private_key"] : [credential_name]
      ]),
      service.credentials.source == "target" ? ["password"] : [],
      service.features.mail ? ["mail_password"] : [],
      service.features.object_storage ? ["object_storage_secret_access_key"] : [],
      service.features.oidc ? concat(
        ["oidc_client_id"],
        try(service.data.oidc_is_public, false) ? [] : ["oidc_client_secret"],
      ) : [],
      service.features.password ? ["password", "password_hash"] : [],
      service.features.tailscale ? ["tailscale_auth_key"] : [],
    )
  }

  _services_validation_credential_names_conflicting = [
    for service_key, credential_names in local._services_validation_credential_names : service_key
    if length(credential_names) != length(distinct(credential_names))
  ]

  _services_validation_fly_ports_missing = [
    for service_key, service in local.services_input : service_key
    if(
      can(service.targets.fly) &&
      service.routing.backend_port == null
    )
  ]

  _services_validation_import_alias_conflicts = flatten([
    for service_key, imports in local.services_model_imports : [
      for import_alias, service_ref in imports : "${service_key}.${import_alias} -> ${service_ref}"
      if can(local.services_model[import_alias])
    ]
  ])

  _services_validation_invalid_imports = flatten([
    for service_key, imports in local.services_model_imports : [
      for import_alias, service_ref in imports : "${service_key}.${import_alias} -> ${service_ref}"
      if !can(local.services_model[service_ref])
    ]
  ])

  _services_validation_invalid_server_imports = flatten([
    for service_key, imports in local.services_model_server_imports : [
      for import_alias, server_ref in imports : "${service_key}.${import_alias} -> ${server_ref}"
      if !can(local.servers_model[server_ref])
    ]
  ])

  _services_validation_invalid_targets = flatten([
    for service_key, service in local.services_input : [
      for target in keys(service.targets) : "${service_key} -> ${target}"
      if(
        target != "fly" &&
        !can(local.servers_model[target])
      )
    ]
  ])

  _services_validation_oidc_callbacks_missing = [
    for service_key, service in local.services_model : service_key
    if(
      service.features.oidc &&
      try(length(service.data.oidc_callback_urls), 0) == 0
    )
  ]

  _services_validation_pocketid_required = (
    var.integrations.pocketid.enabled ? [] : keys(local.services_model_by_feature.oidc)
  )

  _services_validation_proxy_no_port = flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.routes : "${service_key} -> ${route.host}"
      if(
        route.proxy_server != null &&
        route.backend_port == null
      )
    ]
  ])

  _services_validation_proxy_server_missing = flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.routes : "${service_key} -> ${route.proxy_server}"
      if(
        route.proxy_server != null &&
        !can(local.servers_model[route.proxy_server])
      )
    ]
  ])

  _services_validation_redirects_invalid = flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.routes : [
        for redirect in route.redirects : "${service_key} -> ${redirect.host}"
        if(
          redirect.host == route.host ||
          redirect.zone == null ||
          route.href == null ||
          service.target == "fly"
        )
      ]
    ]
  ])

  _services_validation_route_host_entries = flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.routes : concat(
        route.host != null ? [
          {
            host   = route.host
            source = service_key
          }
        ] : [],
        [
          for redirect in route.redirects : {
            host   = redirect.host
            source = service_key
          }
        ],
      )
    ]
  ])

  _services_validation_route_hosts_conflicting = [
    for host, sources in {
      for entry in local._services_validation_route_host_entries : entry.host => entry.source...
    } : "${host} (${join(", ", sources)})"
    if length(sources) > 1
  ]

  _services_validation_route_ids_not_unique = [
    for service_key, service in local.services_model : service_key
    if length(service.routing.routes) != length(distinct([for route in service.routing.routes : route.id]))
  ]

  _services_validation_server_import_alias_conflicts = flatten([
    for service_key, imports in local.services_model_server_imports : [
      for import_alias, server_ref in imports : "${service_key}.${import_alias} -> ${server_ref}"
      if can(local.servers_model[import_alias])
    ]
  ])

  _services_validation_server_routes_missing_traefik = flatten([
    for server_key, server in local.servers_model : [
      for route in server.routing.routes : "${server_key}.${route.host} -> ${startswith(route.expose, "proxy-") ? trimprefix(route.expose, "proxy-") : server_key}"
      if(
        route.expose != "cloudflare" &&
        !contains(
          [
            for service in values(local.services_model) : service.target
            if service.identity.name == "traefik"
          ],
          startswith(route.expose, "proxy-") ? trimprefix(route.expose, "proxy-") : server_key,
        )
      )
    ]
  ])

  _services_validation_target_credentials_invalid = [
    for service_key, service in local.services_model : service_key
    if(
      service.credentials.source == "target" &&
      (
        !can(local.servers_model[service.target]) ||
        !local.servers_model[service.target].features.password
      )
    )
  ]

  _services_validation_target_credentials_password_feature = [
    for service_key, service in local.services_model : service_key
    if(
      service.credentials.source == "target" &&
      service.features.password
    )
  ]

  _services_validation_target_features_invalid = [
    for service_key, service in local.services_input : "${service_key} -> ${service.target_feature}"
    if(
      service.target_feature != "" &&
      !can(local.defaults.servers.features[service.target_feature])
    )
  ]

  _services_validation_truenas_config_invalid_targets = [
    for service_key, service in local.services_model : service_key
    if(
      !can(local.truenas_servers[service.target]) &&
      (
        service.truenas.catalog_app != "" ||
        length(service.truenas.env) > 0 ||
        service.truenas.port_key != local.defaults.targets.truenas.port_key ||
        service.truenas.train != local.defaults.targets.truenas.train
      )
    )
  ]

  _services_validation_truenas_missing_template = [
    for service_key, service in local.truenas_services : service_key
    if(
      !can(local.services_render_compose_inputs[service_key]) &&
      !can(local.truenas_catalog_templates[service_key])
    )
  ]

  _services_validation_unmanaged_hosts = flatten([
    for service_key, service in local.services_model : [
      for route in service.routing.routes : "${service_key} -> ${route.host}"
      if(
        route.host_configured &&
        service.target != "fly" &&
        route.expose != "cloudflare" &&
        route.https &&
        route.zone == null
      )
    ]
  ])
}

resource "terraform_data" "services_validation" {
  input = keys(local.services_input)

  lifecycle {
    precondition {
      condition     = length(local._services_validation_credential_names_conflicting) == 0
      error_message = "Service credential names must not overlap manual fields, generated outputs, or feature-created fields: ${join(", ", local._services_validation_credential_names_conflicting)}"
    }

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
      condition     = length(local._services_validation_fly_ports_missing) == 0
      error_message = "Fly services must have routing.backend_port set: ${join(", ", nonsensitive(local._services_validation_fly_ports_missing))}"
    }

    precondition {
      condition = length([
        for service_key, service in local.services_model : service_key
        if service.identity.name == "homepage"
      ]) == 1
      error_message = "Exactly one expanded service with identity.name = homepage is required for the dashboard to render"
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
      condition = length(local._services_validation_invalid_server_imports) == 0
      error_message = (
        "Invalid server imports found in services configuration: ${join(", ", local._services_validation_invalid_server_imports)}"
      )
    }

    precondition {
      condition = length(local._services_validation_invalid_targets) == 0
      error_message = (
        "Invalid server references found in services configuration: ${join(", ", local._services_validation_invalid_targets)}"
      )
    }

    precondition {
      condition     = length(local._services_validation_oidc_callbacks_missing) == 0
      error_message = "Services with features.oidc enabled require at least one data.oidc_callback_urls entry: ${join(", ", local._services_validation_oidc_callbacks_missing)}"
    }

    precondition {
      condition     = length(local._services_validation_pocketid_required) == 0
      error_message = "Pocket ID must be enabled while services use features.oidc: ${join(", ", local._services_validation_pocketid_required)}"
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
      condition = length(local._services_validation_redirects_invalid) == 0
      error_message = (
        "Service routing redirects require a distinct managed hostname, canonical destination, and non-Fly target: ${join(", ", local._services_validation_redirects_invalid)}"
      )
    }

    precondition {
      condition     = length(local._services_validation_route_hosts_conflicting) == 0
      error_message = "Service routing hostnames and redirects must be globally unique: ${join(", ", local._services_validation_route_hosts_conflicting)}"
    }

    precondition {
      condition     = length(local._services_validation_route_ids_not_unique) == 0
      error_message = "Service routing IDs must be unique per target: ${join(", ", local._services_validation_route_ids_not_unique)}"
    }

    precondition {
      condition = length(local._services_validation_server_import_alias_conflicts) == 0
      error_message = (
        "Server import aliases must not shadow real server keys: ${join(", ", local._services_validation_server_import_alias_conflicts)}"
      )
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
      condition     = length(local._services_validation_target_features_invalid) == 0
      error_message = "Service target_feature must name a server feature: ${join(", ", nonsensitive(local._services_validation_target_features_invalid))}"
    }

    precondition {
      condition = length(local._services_validation_truenas_config_invalid_targets) == 0
      error_message = (
        "targets.<key>.truenas settings are only valid for services targeting TrueNAS servers: ${join(", ", local._services_validation_truenas_config_invalid_targets)}"
      )
    }

    # TrueNAS services need either a catalog app or custom Compose template.
    precondition {
      condition     = length(local._services_validation_truenas_missing_template) == 0
      error_message = "TrueNAS services require app.json.tftpl or docker-compose.yaml.tftpl: ${join(", ", nonsensitive(local._services_validation_truenas_missing_template))}"
    }

    # HTTPS service URLs need managed DNS so ACME delegation can resolve.
    precondition {
      condition = length(local._services_validation_unmanaged_hosts) == 0
      error_message = (
        "Service route hosts must be in a managed DNS zone (data/dns/) for ACME delegation: ${join(", ", local._services_validation_unmanaged_hosts)}"
      )
    }
  }
}
