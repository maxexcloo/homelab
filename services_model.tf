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
        service.features.oidc ? {
          oidc_client_id = merge(
            local.defaults.credentials.rw,
            {
              bootstrap_length = 16
              bootstrap_type   = "hex"
            }
          )
          oidc_client_secret = merge(
            local.defaults.credentials.rw,
            {
              bootstrap_length = 32
              bootstrap_type   = "hex"
            }
          )
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
  # Also indexes by snake_case identity name so aliases like `pocket_id` resolve when the service
  # name is `pocket-id` (templatestring() cannot parse hyphens in attribute access).
  _services_model_import_auto_targets = merge(
    {
      for service_key, service in local.services_input : service_key => "${service_key}-${one(keys(service.targets))}"
      if length(service.targets) == 1
    },
    {
      for service_key, service in local.services_input : join("_", split("-", service.identity.name)) => "${service_key}-${one(keys(service.targets))}"
      if(
        length(service.targets) == 1 &&
        can(regex("-", service.identity.name))
      )
    },
  )

  # Flatten import declarations before resolving aliases to expanded service keys.
  _services_model_import_refs = flatten([
    for service_key, service in local.services_input_targets : [
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

  _services_model_route_entries = {
    for service_key, service in local.services_input_targets : service_key => [
      for route_index, url in concat(
        service.routing.urls,
        (
          service.routing.backend_port != null ||
          service.routing.backend_scheme != ""
          ) ? [
          {
            expose = "internal"
            url    = null
          }
        ] : [],
        ) : merge(
        {
          for field_name, field_value in service.routing : field_name => field_value
          if field_name != "urls"
        },
        url,
        {
          dns_target_host = (
            service.target == "fly" ? "${local._services_model_fly_app_names[service_key]}.fly.dev"
            : startswith(url.expose, "proxy-") ? try(
              "${service.identity.name}.${local.servers_model[trimprefix(url.expose, "proxy-")].hosts.external}",
              null,
            )
            : contains(["cloudflare", "external"], url.expose) ? try(
              "${service.identity.name}.${local.servers_model[service.target].hosts.external}",
              null,
            )
            : url.expose == "internal" && try(url.backend_scheme, service.routing.backend_scheme) != "" ? try(
              "${service.identity.name}.${local.servers_model[service.target].hosts.internal}",
              null,
            )
            : null
          )
          id           = try(url.id, tostring(route_index))
          proxy_server = startswith(url.expose, "proxy-") ? trimprefix(url.expose, "proxy-") : null

          redirects = [
            for redirect in try(url.redirects, []) : {
              acme         = try(url.https, service.routing.https) && !startswith(url.expose, "proxy-")
              expose       = url.expose == "cloudflare" ? "external" : url.expose
              host         = redirect
              name         = "${service.identity.name}-redirect-${substr(sha1(redirect), 0, 12)}"
              proxy_server = startswith(url.expose, "proxy-") ? trimprefix(url.expose, "proxy-") : null
              zone         = try(local.dns_model_managed_zones_by_url[redirect], null)
            }
          ]
        },
      )
    ]
  }

  _services_model_routes = {
    for service_key, service in local.services_input_targets : service_key => [
      for route in local._services_model_route_entries[service_key] : merge(
        route,
        {
          backend_url = route.backend_url
          container   = route.container != "" ? route.container : service.identity.service
          host        = route.url != null ? route.url : route.dns_target_host
          host_port   = route.host_port != null ? route.host_port : route.backend_port
          href        = route.url != null || route.dns_target_host != null ? "${route.https ? "https" : "http"}://${route.url != null ? route.url : route.dns_target_host}" : null
          name        = route.id == "0" ? service.identity.name : "${service.identity.name}-${route.id}"
          zone = route.dns_target_host == null && route.url == null ? null : (
            route.url != null ? local.dns_model_managed_zones_by_url[route.url]
            : service.target == "fly" ? "fly.dev"
            : route.expose == "internal" ? local.defaults.domains.internal
            : local.defaults.domains.external
          )
        },
      )
    ]
  }

  _services_model_target_servers = {
    for service_key, service in local.services_input_targets : service_key => try(local.servers_model[service.target], null)
  }

  _services_model_urls = {
    for service_key, service in local.services_input_targets : service_key => {
      for host, urls in {
        for route in local._services_model_routes[service_key] :
        route.host => {
          host  = route.host
          href  = route.href
          label = route.url != null ? "website" : route.expose
          zone  = route.zone
        }...
        if route.host != null
      } : host => urls[0]
    }
  }

  _services_model_url_aliases = {
    for service_key, service in local.services_input_targets : service_key => {
      default = try(
        [
          for route in local._services_model_routes[service_key] : route.href
          if route.href != null
        ][0],
        null,
      )
      external = try(
        [
          for route in local._services_model_routes[service_key] : route.href
          if route.href != null && (route.url != null || route.expose == "external")
        ][0],
        null,
      )
      internal = try(
        [
          for route in local._services_model_routes[service_key] : route.href
          if route.href != null && route.url == null && route.expose == "internal"
        ][0],
        null,
      )
    }
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

          hosts = {
            external = local._services_model_target_servers[service_key] != null ? "${service.identity.name}.${local._services_model_target_servers[service_key].hosts.external}" : null
            internal = local._services_model_target_servers[service_key] != null ? "${service.identity.name}.${local._services_model_target_servers[service_key].hosts.internal}" : null
          }

          identity = {
            group = (
              service.identity.group != "" ? service.identity.group
              : local._services_model_target_servers[service_key] != null ? local._services_model_target_servers[service_key].identity.group
              : "Applications"
            )
            username = (
              service.credentials.source == "target" &&
              local._services_model_target_servers[service_key] != null
            ) ? local._services_model_target_servers[service_key].identity.username : service.identity.username
          }

          routing = merge(
            {
              for field_name, field_value in service.routing : field_name => field_value
              if field_name != "urls"
            },
            {
              backend_url = service.routing.backend_url
              container   = service.routing.container != "" ? service.routing.container : service.identity.service
              host_port   = service.routing.host_port != null ? service.routing.host_port : service.routing.backend_port
              urls        = local._services_model_routes[service_key]
            },
          )

          urls = merge(
            {
              default = {
                host  = local._services_model_url_aliases[service_key].default != null ? one(regex("^https?://([^/:]+)", local._services_model_url_aliases[service_key].default)) : null
                href  = local._services_model_url_aliases[service_key].default
                label = "default"
                zone  = null
              }
            },
            local._services_model_url_aliases[service_key].external != null ? {
              external = {
                host  = one(regex("^https?://([^/:]+)", local._services_model_url_aliases[service_key].external))
                href  = local._services_model_url_aliases[service_key].external
                label = "external"
                zone  = null
              }
            } : {},
            local._services_model_url_aliases[service_key].internal != null ? {
              internal = {
                host  = one(regex("^https?://([^/:]+)", local._services_model_url_aliases[service_key].internal))
                href  = local._services_model_url_aliases[service_key].internal
                label = "internal"
                zone  = null
              }
            } : {},
            local._services_model_urls[service_key],
          )
        },
      )
    )
  }

  services_model_imports = {
    for service_key in keys(local.services_input_targets) : service_key => {
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
