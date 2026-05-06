locals {
  # Resolved Fly app name per service. coalesce is safe because defaults.yml
  # sets app_name to null, which coalesce skips in favour of the fallback.
  _services_model_fly_app_names = {
    for service_key, service in local.services_input_targets : service_key =>
    service.target == "fly" ? coalesce(service.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}") : service.fly.app_name
  }

  # Desired service model: expanded deployment target data plus deterministic
  # names, URLs, and server FQDNs.
  services_model = {
    for service_key, service in local.services_input_targets : service_key => provider::deepmerge::mergo(
      service,
      {
        fqdn_internal = contains(local.servers_input_keys, service.target) && service.routing.scheme != null ? "${service.identity.name}.${local.servers_model[service.target].fqdn_internal}" : null
        key           = service_key

        fly = {
          app_name = local._services_model_fly_app_names[service_key]
        }

        fqdn_external = (
          service.target == "fly"
          ? "${local._services_model_fly_app_names[service_key]}.fly.dev"
          : contains(local.servers_input_keys, service.target) && contains(["cloudflare", "external"], service.routing.expose)
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
