locals {
  _services_model_fqdns = {
    for service_key, service in local.services_input_targets : service_key => {
      fqdn_internal = local._services_model_target_is_server[service_key] && service.routing.scheme != null ? "${service.identity.name}.${local.servers_model[service.target].fqdn_internal}" : null

      # Fly always gets a fly.dev hostname. Managed-server services only get an
      # external FQDN when explicitly exposed as cloudflare or external; internal
      # and tailscale services are not publicly routable via external DNS.
      fqdn_external = (
        service.target == "fly"
        ? "${coalesce(service.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}")}.fly.dev"
        : local._services_model_target_is_server[service_key] && contains(["cloudflare", "external"], service.routing.expose)
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

  _services_model_import_auto_targets = {
    for service_key, service in local.services_input : service_key => "${service_key}-${keys(service.targets)[0]}"
    if length(service.targets) == 1
  }

  # Render import references before services_render templating so validation can
  # catch missing dependencies instead of failing inside templatestring().
  _services_model_import_refs = flatten([
    for service_key, service in local.services_model : [
      for import_alias, import_ref in service.imports.services : {
        alias       = import_alias
        service_key = service_key
        target = templatestring(
          import_ref,
          {
            service = service
          },
        )
      }
    ]
  ])

  _services_model_server_keys = toset(keys(local.servers_input))

  _services_model_target_is_server = {
    for service_key, service in local.services_input_targets : service_key => contains(local._services_model_server_keys, service.target)
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

  _services_model_url_scheme = {
    for service_key, service in local.services_input_targets : service_key => service.routing.ssl ? "https" : "http"
  }

  _services_model_urls = {
    for service_key, service in local.services_input_targets : service_key => merge(
      {
        for url in service.routing.urls : url => {
          href  = "${local._services_model_url_scheme[service_key]}://${url}"
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
          href  = "${local._services_model_url_scheme[service_key]}://${local._services_model_fqdns[service_key].fqdn_external}"
          label = "fqdn_external"
          zone  = service.target == "fly" ? "fly.dev" : local.defaults.domains.external
        }
      } : {},
      local._services_model_fqdns[service_key].fqdn_internal != null ? {
        fqdn_internal = {
          href  = "${local._services_model_url_scheme[service_key]}://${local._services_model_fqdns[service_key].fqdn_internal}"
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
      for import_ref in local._services_model_import_refs :
      # "auto" imports use the alias as the base service name, then resolve only
      # when that base service has exactly one expanded target.
      import_ref.alias => (
        import_ref.target == "auto"
        ? lookup(local._services_model_import_auto_targets, import_ref.alias, import_ref.alias)
        : import_ref.target
      )
      if import_ref.service_key == service_key
    }
  }
}
