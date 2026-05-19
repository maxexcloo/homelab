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

  # Computed internal/external hostnames used to build _services_model_urls.
  _services_model_hosts = {
    for service_key, service in local.services_input_targets : service_key => {
      # Only externally exposed services get generated external hostnames.
      external = (
        service.target == "fly"
        ? "${coalesce(service.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}")}.fly.dev"
        : lookup(local.servers_model, service.target, null) != null &&
        contains(["cloudflare", "external"], service.routing.expose)
        ? "${service.identity.name}.${local.servers_model[service.target].hosts.external}"
        : local.services_model_proxy_server[service_key] != null &&
        lookup(local.servers_model, local.services_model_proxy_server[service_key], null) != null
        ? "${service.identity.name}.${local.servers_model[local.services_model_proxy_server[service_key]].hosts.external}"
        : null
      )

      internal = (
        lookup(local.servers_model, service.target, null) != null &&
        service.routing.backend_scheme != ""
        ? "${service.identity.name}.${local.servers_model[service.target].hosts.internal}"
        : null
      )
    }
  }

  # Maps single-target services to their expanded key ("service-target") for `auto` import resolution.
  _services_model_import_auto_targets = {
    for service_key, service in local.services_input : service_key => "${service_key}-${keys(service.targets)[0]}"
    if length(service.targets) == 1
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

  # Full URL map per service: custom urls + generated external/internal hostnames.
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
      # Managed custom URLs are the canonical Cloudflare entry point; avoid
      # deep generated hostnames that Universal SSL will not cover.
      local._services_model_hosts[service_key].external != null && !(
        service.routing.expose == "cloudflare" &&
        length(compact([for url in service.routing.urls : lookup(local.dns_render_managed_zones_by_url, url, null)])) > 0
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
  # Extracted to avoid repeating the candidate list for both href and host derivation.
  _services_model_urls_default = {
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

  # Maps each service to the proxy server key used for expose: proxy-{key}.
  services_model_proxy_server = {
    for service_key, service in local.services_input_targets : service_key =>
    service.routing.expose != null && startswith(service.routing.expose, "proxy-") ? trimprefix(service.routing.expose, "proxy-")
    : null
  }

  services_model = {
    for service_key, service in local.services_input_targets : service_key => provider::deepmerge::mergo(
      service,
      merge(
        {
          credentials = local._services_model_credentials[service_key]
          key         = service_key

          fly = {
            app_name = service.target == "fly" ? coalesce(service.fly.app_name, "${local.defaults.organization.name}-${service.identity.name}") : service.fly.app_name
          }

          identity = {
            group   = coalesce(service.identity.group, try(local.servers_model[service.target].description, null), "Applications")
            service = try(service.identity.service, null)
          }

          routing = {
            container = service.routing.container != "" ? service.routing.container : try(service.identity.service, null)
            host_port = try(coalesce(service.routing.host_port, service.routing.backend_port), null)
          }

          urls = merge(
            {
              default = {
                host  = try(regex("^https?://([^/:]+)", local._services_model_urls_default[service_key])[0], null)
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
