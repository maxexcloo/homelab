# Stage: model — adds deterministic computed fields. No provider values; safe for for_each keys.
locals {
  # Credential field shape for each service. Runtime values are added in services_outputs.tf.
  _services_model_credentials = {
    for service_key, service in local.services_input_targets : service_key => {
      fields = merge(
        {
          for field_name, field in service.credentials.fields : field_name => merge(
            local.defaults.credentials.rw,
            field,
          )
        },
        service.features.b2 ? {
          b2_application_key = local.defaults.credentials.ro
        } : {},
        service.features.password ? {
          password_hash = local.defaults.credentials.ro
          password = merge(
            local.defaults.credentials.rw,
            {
              purpose = "PASSWORD"
              type    = null
            }
          )
        } : {},
        service.features.pushover ? {
          pushover_application_token = local.defaults.credentials.rw
          pushover_user_key          = local.defaults.credentials.ro
        } : {},
        service.features.resend ? {
          resend_api_key = local.defaults.credentials.ro
        } : {},
        service.features.tailscale ? {
          tailscale_auth_key = local.defaults.credentials.ro
        } : {},
      )
    }
  }

  # Fly requires stable app names before generated hostnames are computed.
  _services_model_fly_app_names = {
    for service_key, service in local.services_input_targets : service_key =>
    service.fly.app_name != "" ? service.fly.app_name : "${local.defaults.organization.name}-${service.identity.name}"
  }

  # Maps single-target services to their expanded key ("service-target") for `auto` import resolution.
  _services_model_import_auto_targets = {
    for service_key, service in local.services_input : service_key => "${service_key}-${one(keys(service.targets))}"
    if length(service.targets) == 1
  }

  # Managed custom URLs are the canonical Cloudflare entry point.
  _services_model_managed_routing_urls = {
    for service_key, service in local.services_input_targets : service_key => [
      for url in service.routing.urls : url
      if try(local.dns_render_managed_zones_by_url[url], null) != null
    ]
  }

  # Maps each service to the proxy server key used for expose: proxy-{key}.
  services_model_proxy_server = {
    for service_key, service in local.services_input_targets : service_key =>
    (
      service.routing.expose != null &&
      startswith(service.routing.expose, "proxy-")
    ) ? trimprefix(service.routing.expose, "proxy-")
    : null
  }

  _services_model_target_servers = {
    for service_key, service in local.services_input_targets : service_key => try(local.servers_model[service.target], null)
  }

  # Computed internal/external hostnames used to build _services_model_urls.
  _services_model_hosts = {
    for service_key, service in local.services_input_targets : service_key => {
      # Only externally exposed services get generated external hostnames.
      external = (
        service.target == "fly"
        ? "${local._services_model_fly_app_names[service_key]}.fly.dev"
        : (
          local._services_model_target_servers[service_key] != null &&
          contains(["cloudflare", "external"], service.routing.expose)
        )
        ? "${service.identity.name}.${local._services_model_target_servers[service_key].hosts.external}"
        : local.services_model_proxy_server[service_key] != null
        ? try("${service.identity.name}.${local.servers_model[local.services_model_proxy_server[service_key]].hosts.external}", null)
        : null
      )

      internal = (
        (
          local._services_model_target_servers[service_key] != null &&
          service.routing.backend_scheme != ""
        )
        ? "${service.identity.name}.${local._services_model_target_servers[service_key].hosts.internal}"
        : null
      )
    }
  }

  # Full URL map per service: custom urls + generated external/internal hostnames.
  # Cloudflare custom URLs suppress the generated external hostname (Universal SSL only covers one subdomain level).
  _services_model_urls = {
    for service_key, service in local.services_input_targets : service_key => merge(
      {
        for url in service.routing.urls : url => {
          host  = url
          href  = "${service.routing.https ? "https" : "http"}://${url}"
          label = "website"
          zone  = local.dns_render_managed_zones_by_url[url]
        }
      },
      (
        local._services_model_hosts[service_key].external != null &&
        !(
          service.routing.expose == "cloudflare" &&
          length(local._services_model_managed_routing_urls[service_key]) > 0
        )
      ) ? {
        external = {
          host  = local._services_model_hosts[service_key].external
          href  = "${service.routing.https ? "https" : "http"}://${local._services_model_hosts[service_key].external}"
          label = "external"
          zone  = service.target == "fly" ? "fly.dev" : local.defaults.domains.external
        }
      } : {},
      local._services_model_hosts[service_key].internal != null ? {
        internal = {
          host  = local._services_model_hosts[service_key].internal
          href  = "${service.routing.https ? "https" : "http"}://${local._services_model_hosts[service_key].internal}"
          label = "internal"
          zone  = local.defaults.domains.internal
        }
      } : {},
    )
  }

  # First non-null href in priority order: custom url > external > internal.
  _services_model_urls_default = {
    for service_key, service in local.services_input_targets : service_key => try(
      local._services_model_urls[service_key][service.routing.urls[0]].href,
      local._services_model_urls[service_key].external.href,
      local._services_model_urls[service_key].internal.href,
      null,
    )
  }

  # Host used by DNS and Cloudflare when no custom URL is present.
  _services_model_urls_fallback_host = {
    for service_key, service in local.services_input_targets : service_key => try(
      local._services_model_urls[service_key].external.host,
      local._services_model_urls[service_key].internal.host,
      null,
    )
  }

  services_model = {
    for service_key, service in local.services_input_targets : service_key => provider::deepmerge::mergo(
      service,
      merge(
        {
          credentials = local._services_model_credentials[service_key]
          key         = service_key

          fly = {
            app_name = service.target == "fly" ? local._services_model_fly_app_names[service_key] : service.fly.app_name
          }

          identity = {
            group = (
              service.identity.group != "" ? service.identity.group
              : local._services_model_target_servers[service_key] != null ? local._services_model_target_servers[service_key].description
              : "Applications"
            )
            username = (
              service.credentials.source == "target" &&
              local._services_model_target_servers[service_key] != null
            ) ? local._services_model_target_servers[service_key].identity.username : service.identity.username
          }

          routing = {
            backend_url = service.routing.backend_url != "" ? service.routing.backend_url : "http://localhost:8000"
            cloudflare_hostnames = distinct(concat(
              local._services_model_urls_fallback_host[service_key] != null ? [local._services_model_urls_fallback_host[service_key]] : [],
              local._services_model_managed_routing_urls[service_key],
            ))
            container       = service.routing.container != "" ? service.routing.container : service.identity.service
            dns_target_host = local._services_model_urls_fallback_host[service_key]
            host_port       = service.routing.host_port != null ? service.routing.host_port : service.routing.backend_port
          }

          urls = merge(
            {
              default = {
                host  = local._services_model_urls_default[service_key] != null ? one(regex("^https?://([^/:]+)", local._services_model_urls_default[service_key])) : null
                href  = local._services_model_urls_default[service_key]
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

  # Flattened list of import alias declarations across all services. Self-references
  # services_model, which is valid because OpenTofu resolves local dependencies lazily —
  # the reference only reads keys and import declarations, not values produced by this local.
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

  services_model_imports = {
    for service_key, service in local.services_model : service_key => {
      for import_ref in local._services_model_import_refs :
      # `auto` resolves only when the imported service has one expanded target.
      import_ref.alias => (
        import_ref.target == "auto"
        ? try(local._services_model_import_auto_targets[import_ref.alias], import_ref.alias)
        : import_ref.target
      )
      if import_ref.service_key == service_key
    }
  }
}
