locals {
  # Cloudflare Universal SSL covers only one subdomain level.
  services_validation_cloudflare_deep_subdomains = [
    for record_key, record in local.dns_render_records_services : "${record_key} (${record.name})"
    if length(split(".", record.name)) - length(split(".", record.zone)) > 1 &&
    try(record.proxied, false)
  ]

  services_validation_cloudflare_tunnel_missing = flatten([
    for service_key, service in local.services_input : [
      for target in keys(service.targets) : "${service_key} -> ${target}"
      if lookup(local.servers_input, target, null) != null &&
      !local.servers_model[target].features.cloudflare_zero_trust_tunnel &&
      service.routing.expose == "cloudflare"
    ]
  ])

  services_validation_file_key_mismatches = [
    for service_key, service in local.services_input : "${service_key} -> ${service.identity.name}"
    if service_key != service.identity.name
  ]

  services_validation_fly_ports_missing = [
    for service_key, service in local.services_input : service_key
    if lookup(service.targets, "fly", null) != null &&
    service.routing.port == null
  ]

  services_validation_import_alias_conflicts = flatten([
    for service_key, imports in local.services_model_imports : [
      for import_alias, service_ref in imports : "${service_key}.${import_alias} -> ${service_ref}"
      if lookup(local.services_model, import_alias, null) != null
    ]
  ])

  services_validation_invalid_imports = flatten([
    for service_key, imports in local.services_model_imports : [
      for import_alias, service_ref in imports : "${service_key}.${import_alias} -> ${service_ref}"
      if lookup(local.services_model, service_ref, null) == null
    ]
  ])

  services_validation_invalid_targets = flatten([
    for service_key, service in local.services_input : [
      for target in keys(service.targets) : "${service_key} -> ${target}"
      if lookup(local.servers_input, target, null) == null &&
      target != "fly"
    ]
  ])

  services_validation_truenas_config_invalid_targets = [
    for service_key, service in local.services_model : service_key
    if lookup(local.truenas_input_servers, service.target, null) == null &&
    (
      service.truenas.catalog_app != null ||
      length(service.truenas.env) > 0 ||
      service.truenas.port_key != local.defaults.targets.truenas.port_key ||
      service.truenas.train != local.defaults.targets.truenas.train
    )
  ]

  services_validation_truenas_missing_template = [
    for service_key, service in local.truenas_input_services : service_key
    if lookup(local.services_render_files_compose, service_key, null) == null &&
    lookup(local.truenas_prepare_catalog_templates, service_key, null) == null
  ]

  services_validation_unmanaged_urls = flatten([
    for service_key, service in local.services_model : [
      for url in service.routing.urls : "${service_key} -> ${url}"
      if lookup(local.dns_render_managed_zones_by_url, url, null) == null &&
      service.routing.expose != "cloudflare" &&
      service.routing.ssl &&
      service.target != "fly"
    ]
  ])
}

resource "terraform_data" "services_validation" {
  input = keys(local.services_input)

  lifecycle {
    # Deep generated service hostnames need custom short URLs or dedicated certs.
    precondition {
      condition     = length(local.services_validation_cloudflare_deep_subdomains) == 0
      error_message = "Cloudflare-proxied hostnames exceed Universal SSL coverage (max one subdomain level): ${join(", ", local.services_validation_cloudflare_deep_subdomains)}"
    }

    # Cloudflare-exposed server services need a tunnel on the target server.
    precondition {
      condition = length(local.services_validation_cloudflare_tunnel_missing) == 0
      error_message = (
        "Cloudflare-exposed services deployed to servers require cloudflare_zero_trust_tunnel on the target server: ${join(", ", local.services_validation_cloudflare_tunnel_missing)}"
      )
    }

    precondition {
      condition     = length(local.services_validation_fly_ports_missing) == 0
      error_message = "Fly services must have routing.port set: ${join(", ", local.services_validation_fly_ports_missing)}"
    }

    precondition {
      condition = length(local.services_validation_file_key_mismatches) == 0
      error_message = (
        "Service YAML filenames must match identity.name: ${join(", ", local.services_validation_file_key_mismatches)}"
      )
    }

    precondition {
      condition = length(local.services_validation_import_alias_conflicts) == 0
      error_message = (
        "Service import aliases must not shadow real service keys: ${join(", ", local.services_validation_import_alias_conflicts)}"
      )
    }

    precondition {
      condition = length(local.services_validation_invalid_imports) == 0
      error_message = (
        "Invalid service imports found in services configuration: ${join(", ", local.services_validation_invalid_imports)}"
      )
    }

    precondition {
      condition = length(local.services_validation_invalid_targets) == 0
      error_message = (
        "Invalid server references found in services configuration: ${join(", ", local.services_validation_invalid_targets)}"
      )
    }

    precondition {
      condition = length(local.services_validation_truenas_config_invalid_targets) == 0
      error_message = (
        "targets.<key>.truenas settings are only valid for services targeting TrueNAS servers: ${join(", ", local.services_validation_truenas_config_invalid_targets)}"
      )
    }

    # TrueNAS services need either a custom compose template or catalog template.
    precondition {
      condition     = length(local.services_validation_truenas_missing_template) == 0
      error_message = "TrueNAS catalog services require templates/services/{identity.service}/app.json.tftpl: ${join(", ", local.services_validation_truenas_missing_template)}"
    }

    # SSL service URLs need managed DNS so ACME delegation can resolve.
    precondition {
      condition = length(local.services_validation_unmanaged_urls) == 0
      error_message = (
        "Service routing.urls must be in a managed DNS zone (data/dns/) for ACME delegation: ${join(", ", local.services_validation_unmanaged_urls)}"
      )
    }
  }
}
