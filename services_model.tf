locals {
  _services_model_groups = {
    for service_key, service in local.services_input_targets : service_key => coalesce(
      service.identity.group,
      try(local.servers_model[service.target].description, null),
      "Applications",
    )
  }

  _services_model_hosts = {
    for service_key, service in local.services_input_targets : service_key => {
      internal = local._services_model_target_is_server[service_key] && service.routing.scheme != null ? "${service.identity.name}.${local.servers_model[service.target].hosts.internal}" : null

      # Only externally exposed services get generated external hostnames.
      external = (
        service.target == "fly"
        ? "${coalesce(service.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}")}.fly.dev"
        : local._services_model_target_is_server[service_key] && contains(["cloudflare", "external"], service.routing.expose)
        ? "${service.identity.name}.${local.servers_model[service.target].hosts.external}"
        : null
      )
    }
  }

  _services_model_import_auto_targets = {
    for service_key, service in local.services_input : service_key => "${service_key}-${keys(service.targets)[0]}"
    if length(service.targets) == 1
  }

  # Render import references before services_render templating so missing
  # dependencies fail validation, not templatestring().
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

  _services_model_url_scheme = {
    for service_key, service in local.services_input_targets : service_key => service.routing.ssl ? "https" : "http"
  }

  _services_model_urls = {
    for service_key, service in local.services_input_targets : service_key => merge(
      {
        for url in service.routing.urls : url => {
          host  = url
          href  = "${local._services_model_url_scheme[service_key]}://${url}"
          label = "website"
          zone  = local.dns_render_managed_zones_by_url[url]
        }
      },
      # Managed custom URLs are the canonical Cloudflare entry point; avoid
      # deep generated hostnames that Universal SSL will not cover.
      local._services_model_hosts[service_key].external != null && !(
        service.routing.expose == "cloudflare" &&
        length(compact([for url in service.routing.urls : lookup(local.dns_render_managed_zones_by_url, url, null)])) > 0
        ) ? {
        external = {
          host  = local._services_model_hosts[service_key].external
          href  = "${local._services_model_url_scheme[service_key]}://${local._services_model_hosts[service_key].external}"
          label = "external"
          zone  = service.target == "fly" ? "fly.dev" : local.defaults.domains.external
        }
      } : {},
      local._services_model_hosts[service_key].internal != null ? {
        internal = {
          host  = local._services_model_hosts[service_key].internal
          href  = "${local._services_model_url_scheme[service_key]}://${local._services_model_hosts[service_key].internal}"
          label = "internal"
          zone  = local.defaults.domains.internal
        }
      } : {},
    )
  }

  _services_model_urls_candidate_href = {
    for service_key, service in local.services_input_targets : service_key => concat(
      [
        for candidate in [
          length(service.routing.urls) > 0 ? local._services_model_urls[service_key][service.routing.urls[0]].href : null,
          try(local._services_model_urls[service_key].external.href, null),
          try(local._services_model_urls[service_key].internal.href, null),
        ] : candidate
        if candidate != null && candidate != ""
      ],
      [null],
    )[0]
  }

  _services_model_urls_default = {
    for service_key, href in local._services_model_urls_candidate_href : service_key => {
      host = href != null ? regex("^https?://([^/:]+)", href)[0] : null
      href = href
    }
  }

  services_model = {
    for service_key, service in local.services_input_targets : service_key => provider::deepmerge::mergo(
      service,
      merge(
        {
          key = service_key

          fly = {
            app_name = service.target == "fly" ? coalesce(service.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}") : service.fly.app_name
          }

          identity = {
            group   = local._services_model_groups[service_key]
            service = try(service.identity.service, null)
          }

          routing = {
            container = service.routing.container != null ? service.routing.container : try(service.identity.service, null)
          }

          secrets = [
            for secret in service.secrets : merge(
              {
                bootstrap_length = null
                bootstrap_type   = null
              },
              secret
            )
          ]

          urls = merge(
            {
              default = {
                host  = local._services_model_urls_default[service_key].host
                href  = local._services_model_urls_default[service_key].href
                label = "default"
                zone  = null
              }
            },
            local._services_model_urls[service_key],
          )
        },
      )
    )
  }

  services_model_imports = {
    for service_key, service in local.services_model : service_key => {
      for import_ref in local._services_model_import_refs :
      # `auto` resolves only when the imported service has one expanded target.
      import_ref.alias => (
        import_ref.target == "auto"
        ? lookup(local._services_model_import_auto_targets, import_ref.alias, import_ref.alias)
        : import_ref.target
      )
      if import_ref.service_key == service_key
    }
  }
}
