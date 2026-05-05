locals {
  # Resolved Fly app name per service. coalesce is safe because defaults.yml
  # sets app_name to null, which coalesce skips in favour of the fallback.
  _services_model_fly_app_names = {
    for service_key, service in local.services_input_targets : service_key =>
    service.target == "fly" ? coalesce(service.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}") : service.fly.app_name
  }

  # Generated bootstrap value per declared service secret. Null when the secret
  # has no bootstrap_type — those are operator-supplied via 1Password and the
  # state secret falls through to an empty placeholder until populated.
  _services_model_secret_bootstrap = {
    for entry in flatten([
      for service_key, service in local.services_input_targets : [
        for secret in service.features.secrets : {
          key = "${service_key}-${secret.name}"
          value = (
            try(secret.bootstrap_type, null) == "hex" ? random_id.service_secret["${service_key}-${secret.name}"].hex
            : try(secret.bootstrap_type, null) == "base64" ? random_id.service_secret["${service_key}-${secret.name}"].b64_std
            : contains(["alphanumeric", "string"], try(secret.bootstrap_type, "")) ? random_password.service_secret["${service_key}-${secret.name}"].result
            : null
          )
        }
      ]
    ]) : entry.key => entry.value
  }

  # Desired service model: expanded deployment target data plus deterministic
  # names, URLs, and server FQDNs.
  services_model = {
    for service_key, service in local.services_input_targets : service_key => provider::deepmerge::mergo(
      service,
      {
        fqdn_internal = contains(local.servers_input_keys, service.target) && service.networking.scheme != null ? "${service.identity.name}.${local.servers_model[service.target].fqdn_internal}" : null
        key           = service_key

        fly = {
          app_name = local._services_model_fly_app_names[service_key]
        }

        fqdn_external = (
          service.target == "fly"
          ? "${local._services_model_fly_app_names[service_key]}.fly.dev"
          : contains(local.servers_input_keys, service.target) && contains(["cloudflare", "external"], service.networking.expose)
          ? "${service.identity.name}.${local.servers_model[service.target].fqdn_external}"
          : null
        )

        identity = {
          group = coalesce(
            service.identity.group,
            try(local.servers_model[service.target].description, null),
            "Applications",
          )
        }
      }
    )
  }
}
