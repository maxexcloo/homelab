locals {
  _services_model_fqdns = {
    for service_key, service in local.services_input_targets : service_key => {
      fqdn_internal = contains(toset(keys(local.servers_input)), service.target) && service.routing.scheme != null ? "${service.identity.name}.${local.servers_model[service.target].fqdn_internal}" : null

      # Fly always gets a fly.dev hostname. Managed-server services only get an
      # external FQDN when explicitly exposed as cloudflare or external; internal
      # and tailscale services are not publicly routable via external DNS.
      fqdn_external = (
        service.target == "fly"
        ? "${coalesce(service.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}")}.fly.dev"
        : contains(toset(keys(local.servers_input)), service.target) && contains(["cloudflare", "external"], service.routing.expose)
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

  _services_model_url = {
    for service_key, service in local.services_input_targets : service_key => concat(
      [
        for candidate in [
          length(service.routing.urls) > 0 ? local._services_model_urls[service_key][service.routing.urls[0]].href : null,
          try(local._services_model_urls[service_key].fqdn_external.href, null),
          try(local._services_model_urls[service_key].fqdn_internal.href, null),
        ] : candidate
        if candidate != null && candidate != ""
      ],
      [null],
    )[0]
  }

  _services_model_urls = {
    for service_key, service in local.services_input_targets : service_key => merge(
      {
        for url in service.routing.urls : url => {
          href  = "${service.routing.ssl ? "https" : "http"}://${url}"
          label = "website"
          zone  = local.dns_render_zones_urls[url]
        }
      },
      # Skip auto-generated fqdn_external when cloudflare-exposed and custom URLs
      # already have managed DNS zones — those URLs are the canonical entry point.
      local._services_model_fqdns[service_key].fqdn_external != null && !(
        service.routing.expose == "cloudflare" &&
        length(compact([for url in service.routing.urls : lookup(local.dns_render_zones_urls, url, null)])) > 0
        ) ? {
        fqdn_external = {
          href  = "${service.routing.ssl ? "https" : "http"}://${local._services_model_fqdns[service_key].fqdn_external}"
          label = "fqdn_external"
          zone  = service.target == "fly" ? "fly.dev" : local.defaults.domains.external
        }
      } : {},
      local._services_model_fqdns[service_key].fqdn_internal != null ? {
        fqdn_internal = {
          href  = "${service.routing.ssl ? "https" : "http"}://${local._services_model_fqdns[service_key].fqdn_internal}"
          label = "fqdn_internal"
          zone  = local.defaults.domains.internal
        }
      } : {},
    )
  }

  services_model = {
    for service_key, service in local.services_input_targets : service_key => provider::deepmerge::mergo(
      service,
      merge(
        local._services_model_fqdns[service_key],
        {
          fqdn         = local._services_model_url[service_key] != null ? regex("^https?://([^/:]+)", local._services_model_url[service_key])[0] : null
          key          = service_key
          url          = local._services_model_url[service_key]
          url_external = try(local._services_model_urls[service_key].fqdn_external.href, null)
          url_internal = try(local._services_model_urls[service_key].fqdn_internal.href, null)
          urls         = local._services_model_urls[service_key]

          dashboard = [
            for dashboard_card in [
              for input_card in jsondecode(jsonencode(service.dashboard)) : merge(local.defaults.services.dashboard[0], input_card)
              ] : {
              container   = dashboard_card.container
              description = coalesce(dashboard_card.description, service.identity.description)
              group       = coalesce(dashboard_card.group, local._services_model_groups[service_key])
              href        = concat([for candidate in [dashboard_card.href, local._services_model_url[service_key]] : candidate if candidate != null && candidate != ""], [null])[0]
              icon        = coalesce(dashboard_card.icon, service.identity.name)
              name        = coalesce(dashboard_card.name, service.identity.title)
              siteMonitor = service.features.monitoring ? concat([for candidate in [dashboard_card.siteMonitor, dashboard_card.href, local._services_model_url[service_key]] : candidate if candidate != null && candidate != ""], [null])[0] : null
              widgets     = dashboard_card.widgets
            }
          ]

          fly = {
            app_name = service.target == "fly" ? coalesce(service.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}") : service.fly.app_name
          }

          identity = {
            group = local._services_model_groups[service_key]
          }

          routing = {
            container = coalesce(service.routing.container, service.identity.service)
          }

          secrets = [
            for secret in service.secrets : merge(
              {
                bootstrap_length = null,
                bootstrap_type   = null
              },
              secret
            )
          ]
        },
      )
    )
  }

  services_model_imports = {
    for service_key, service in local.services_model : service_key => {
      for import_alias, service_ref in {
        for import_alias, import_ref in service.imports.services : import_alias => templatestring(
          import_ref,
          {
            service = service
          },
        )
      } :
      # "auto" resolves the import alias to a same-named service when that
      # service has exactly one target. Ambiguous or missing targets fall
      # through to services_validation_invalid_imports.
      import_alias => (
        contains(keys(local.services_input), service_ref == "auto" ? import_alias : service_ref) &&
        length(local.services_input[service_ref == "auto" ? import_alias : service_ref].targets) == 1
        ? "${service_ref == "auto" ? import_alias : service_ref}-${keys(local.services_input[service_ref == "auto" ? import_alias : service_ref].targets)[0]}"
        : service_ref == "auto" ? import_alias : service_ref
      )
    }
  }
}
