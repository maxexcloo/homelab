locals {
  _services_model_fqdns = {
    for service_key, service in local.services_input_targets : service_key => {
      fqdn_internal = contains(local.servers_input_keys, service.target) && service.routing.scheme != null ? "${service.identity.name}.${local.servers_model[service.target].fqdn_internal}" : null

      # Fly always gets a fly.dev hostname. Managed-server services only get an
      # external FQDN when explicitly exposed as cloudflare or external; internal
      # and tailscale services are not publicly routable via external DNS.
      fqdn_external = (
        service.target == "fly"
        ? "${coalesce(service.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}")}.fly.dev"
        : contains(local.servers_input_keys, service.target) && contains(["cloudflare", "external"], service.routing.expose)
        ? "${service.identity.name}.${local.servers_model[service.target].fqdn_external}"
        : null
      )
    }
  }

  _services_model_groups = {
    for service_key, service in local.services_input_targets : service_key => coalesce(
      service.identity.group,
      try(local.servers_model[service.target].description, null),
      "Applications",
    )
  }

  _services_model_urls = {
    for service_key, service in local.services_input_targets : service_key => concat(
      [
        for url in service.routing.urls : {
          href  = "${service.routing.ssl ? "https" : "http"}://${url}"
          label = "website"
          zone  = local.dns_render_zones_urls[url]
        }
      ],
      local._services_model_fqdns[service_key].fqdn_external != null && !(
        service.routing.expose == "cloudflare" &&
        length(compact([for url in service.routing.urls : lookup(local.dns_render_zones_urls, url, null)])) > 0
        ) ? [{
          href  = "${service.routing.ssl ? "https" : "http"}://${local._services_model_fqdns[service_key].fqdn_external}"
          label = "fqdn_external"
          zone  = service.target == "fly" ? "fly.dev" : local.defaults.domains.external
      }] : [],
      local._services_model_fqdns[service_key].fqdn_internal != null ? [{
        href  = "${service.routing.ssl ? "https" : "http"}://${local._services_model_fqdns[service_key].fqdn_internal}"
        label = "fqdn_internal"
        zone  = local.defaults.domains.internal
      }] : [],
    )
  }

  services_model = {
    for service_key, service in local.services_input_targets : service_key => provider::deepmerge::mergo(
      service,
      merge(
        local._services_model_fqdns[service_key],
        {
          key  = service_key
          urls = local._services_model_urls[service_key]

          dashboard = merge(service.dashboard, {
            description = coalesce(service.dashboard.description, service.identity.description)
            group       = coalesce(service.dashboard.group, local._services_model_groups[service_key])
            href        = try(coalesce(service.dashboard.href, try(local._services_model_urls[service_key][0].href, null)), null)
            icon        = coalesce(service.dashboard.icon, service.identity.name)
            name        = coalesce(service.dashboard.name, service.identity.title)
            siteMonitor = service.features.monitoring ? try(coalesce(service.dashboard.href, try(local._services_model_urls[service_key][0].href, null)), null) : null
          })

          fly = {
            app_name = service.target == "fly" ? coalesce(service.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}") : service.fly.app_name
          }

          identity = {
            group = local._services_model_groups[service_key]
          }
        },
      )
    )
  }

  services_model_imports = {
    for service_key, service in local.services_model : service_key => {
      for import_alias, service_ref in service.imports.services :
      import_alias => templatestring(service_ref, {
        service = service
      })
    }
  }
}
