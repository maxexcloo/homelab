locals {
  services_validation_cloudflare_tunnel_missing = flatten([
    for service_key, service in local.services_input : [
      for target in keys(service.targets) : "${service_key} -> ${target}"
      if contains(local.servers_input_keys, target) &&
      service.networking.expose == "cloudflare" &&
      !local.servers_model[target].features.cloudflare_zero_trust_tunnel
    ]
  ])

  services_validation_file_key_mismatches = [
    for service_key, service in local.services_input : "${service_key} -> ${service.identity.name}"
    if service_key != service.identity.name
  ]

  services_validation_fly_ports_missing = [
    for service_key, service in local.services_input : service_key
    if contains(keys(service.targets), "fly") && service.networking.port == null
  ]

  services_validation_import_alias_conflicts = flatten([
    for service_key, service in local.services_model : [
      for import_alias, service_ref in service.imports.services : "${service_key}.${import_alias} -> ${templatestring(service_ref, {
        service = service
      })}"
      if contains(keys(local.services_model), import_alias)
    ]
  ])

  services_validation_invalid_imports = flatten([
    for service_key, service in local.services_model : [
      for import_alias, service_ref in service.imports.services : "${service_key}.${import_alias} -> ${templatestring(service_ref, {
        service = service
      })}"
      if !contains(keys(local.services_model), templatestring(service_ref, {
        service = service
      }))
    ]
  ])

  services_validation_invalid_targets = flatten([
    for service_key, service in local.services_input : [
      for target in keys(service.targets) : "${service_key} -> ${target}"
      if !contains(local.servers_input_keys, target) && target != "fly"
    ]
  ])

  services_validation_pushover_missing_credentials = [
    for service_key, service in local.services_input_targets : service_key
    if service.features.pushover && (nonsensitive(var.pushover_application_token) == "" || nonsensitive(var.pushover_user_key) == "")
  ]
}

resource "terraform_data" "services_validation" {
  input = keys(local.services_input)

  lifecycle {
    # Cloudflare-exposed services on servers need a tunnel token available from
    # the target server feature set.
    precondition {
      condition = length(local.services_validation_cloudflare_tunnel_missing) == 0
      error_message = (
        "Cloudflare-exposed services deployed to servers require cloudflare_zero_trust_tunnel on the target server: ${join(", ", local.services_validation_cloudflare_tunnel_missing)}"
      )
    }

    precondition {
      condition     = length(local.services_validation_fly_ports_missing) == 0
      error_message = "Fly services must have networking.port set: ${join(", ", local.services_validation_fly_ports_missing)}"
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

    # Pushover values are pass-through variables, so provider validation will not
    # catch missing credentials for enabled services.
    precondition {
      condition = length(local.services_validation_pushover_missing_credentials) == 0
      error_message = (
        "Services with features.pushover enabled require pushover_application_token and pushover_user_key: ${join(", ", local.services_validation_pushover_missing_credentials)}"
      )
    }
  }
}
