# Stage: model — adds deterministic computed fields. No provider values; safe for for_each keys.
locals {
  _services_model_configured_hosts = distinct(flatten([
    for service in values(local.services_input_targets) : [
      for route in service.routing.routes : concat(
        route.host != null ? [route.host] : [],
        try(route.redirects, []),
      )
    ]
  ]))

  # Credential field shape for each service. Runtime values are added in runtime.tf.
  _services_model_credentials = {
    for service_key, service in local.services_input_targets : service_key => {
      fields = merge(
        {
          for field_name, field in service.credentials.fields : field_name => merge(
            local.defaults.credentials.rw,
            field,
          )
        },
        merge({}, [
          for credential_name, generator in local._services_model_generated_credentials[service_key] :
          generator.type == "x509" ? {
            "${credential_name}_certificate" = local.defaults.credentials.ro
            "${credential_name}_private_key" = local.defaults.credentials.ro
            } : {
            (credential_name) = local.defaults.credentials.rw
          }
        ]...),
        service.features.mail ? {
          mail_password = local.defaults.credentials.ro
        } : {},
        service.features.object_storage ? {
          object_storage_secret_access_key = local.defaults.credentials.ro
        } : {},
        service.features.oidc ? merge(
          {
            oidc_client_id = local.defaults.credentials.ro
          },
          try(service.data.oidc_is_public, false) ? {} : {
            oidc_client_secret = local.defaults.credentials.ro
          },
        ) : {},
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
        service.features.tailscale ? {
          tailscale_auth_key = local.defaults.credentials.ro
        } : {},
      )
      generated = local._services_model_generated_credentials[service_key]
    }
  }

  _services_model_dashboards = {
    for service_key, service in local.services_input_targets : service_key => [
      for card in service.dashboard : merge(
        {
          description = local._services_model_identities[service_key].description
          group       = local._services_model_identities[service_key].group
          icon        = service.identity.service
          name        = local._services_model_identities[service_key].title
        },
        local._services_model_url_aliases[service_key].default != null ? {
          href        = local._services_model_url_aliases[service_key].default.href
          siteMonitor = local._services_model_url_aliases[service_key].default.href
        } : {},
        card,
      )
    ]
  }

  # Fly requires stable app names before generated hostnames are computed.
  _services_model_fly_app_names = {
    for service_key, service in local.services_input_targets : service_key =>
    service.fly.app_name != "" ? service.fly.app_name : "${local.defaults.organization.name}-${service.identity.name}"
  }

  _services_model_generated_credentials = {
    for service_key, service in local.services_input_targets : service_key => merge(
      service.credentials.generated,
      service.features.password ? {
        password = {
          length = 32
          type   = "alphanumeric"
        }
      } : {},
    )
  }

  _services_model_identities = {
    for service_key, service in local.services_input_targets : service_key => merge(
      service.identity,
      {
        group = (
          service.identity.group != "" ? service.identity.group
          : local._services_model_target_servers[service_key] != null ? local._services_model_target_servers[service_key].identity.group
          : "Applications"
        )
        username = (
          service.credentials.source == "target" &&
          local._services_model_target_servers[service_key] != null
        ) ? local._services_model_target_servers[service_key].identity.username : service.identity.username
      },
    )
  }

  _services_model_managed_zone_matches = {
    for host in local._services_model_configured_hosts : host => [
      for zone in keys(local.dns_input) : {
        length = length(zone)
        name   = zone
      }
      if(
        host == zone ||
        endswith(host, ".${zone}")
      )
    ]
  }

  _services_model_managed_zones_by_host = {
    for host, matches in local._services_model_managed_zone_matches : host => try(
      one([for match in matches : match.name if match.length == max(matches[*].length...)]),
      null,
    )
  }

  _services_model_route_inputs = {
    for service_key, service in local.services_input_targets : service_key => [
      for route_index, route in concat(
        service.routing.routes,
        (
          service.routing.backend_port != null ||
          service.routing.backend_scheme != ""
          ) ? [
          {
            expose = "internal"
            host   = null
          }
        ] : [],
        ) : merge(
        {
          for field_name, field_value in service.routing : field_name => field_value
          if field_name != "routes"
        },
        route,
        {
          id              = try(route.id, tostring(route_index))
          host_configured = route.host != null
          proxy_server    = startswith(route.expose, "proxy-") ? trimprefix(route.expose, "proxy-") : null

          dns_target_host = (
            service.target == "fly" ? "${local._services_model_fly_app_names[service_key]}.fly.dev"
            : startswith(route.expose, "proxy-") ? try(
              "${service.identity.name}.${local.servers_model[trimprefix(route.expose, "proxy-")].hosts.external}",
              null,
            )
            : contains(["cloudflare", "external"], route.expose) ? try(
              "${service.identity.name}.${local.servers_model[service.target].hosts.external}",
              null,
            )
            : (
              route.expose == "internal" &&
              try(route.backend_scheme, service.routing.backend_scheme) != ""
              ) ? try(
              "${service.identity.name}.${local.servers_model[service.target].hosts.internal}",
              null,
            )
            : null
          )

          redirects = [
            for redirect in try(route.redirects, []) : {
              expose       = route.expose == "cloudflare" ? "external" : route.expose
              host         = redirect
              name         = "${service.identity.name}-redirect-${substr(sha1(redirect), 0, 12)}"
              proxy_server = startswith(route.expose, "proxy-") ? trimprefix(route.expose, "proxy-") : null
              zone         = try(local._services_model_managed_zones_by_host[redirect], null)

              acme = (
                try(route.https, service.routing.https) &&
                !startswith(route.expose, "proxy-")
              )
            }
          ]
        },
      )
    ]
  }

  _services_model_routes = {
    for service_key, service in local.services_input_targets : service_key => [
      for route in local._services_model_route_inputs[service_key] : merge(
        route,
        {
          backend_url = route.backend_url
          container   = route.container != "" ? route.container : service.identity.service
          host        = route.host_configured ? route.host : route.dns_target_host
          host_port   = route.host_port != null ? route.host_port : route.backend_port
          name        = route.id == "0" ? service.identity.name : "${service.identity.name}-${route.id}"

          acme = (
            route.https &&
            route.proxy_server == null
          )
          href = (
            route.host_configured ||
            route.dns_target_host != null
          ) ? "${route.https ? "https" : "http"}://${route.host_configured ? route.host : route.dns_target_host}" : null
          zone = (
            route.dns_target_host == null &&
            !route.host_configured
            ) ? null : (
            route.host_configured ? local._services_model_managed_zones_by_host[route.host]
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

  _services_model_url_aliases = {
    for service_key, service in local.services_input_targets : service_key => {
      default = try(
        [
          for route in local._services_model_routes[service_key] : route
          if route.href != null
        ][0],
        null,
      )
      external = try(
        [
          for route in local._services_model_routes[service_key] : route
          if(
            route.href != null &&
            (
              route.host_configured ||
              route.expose == "external"
            )
          )
        ][0],
        null,
      )
      internal = try(
        [
          for route in local._services_model_routes[service_key] : route
          if(
            route.href != null &&
            !route.host_configured &&
            route.expose == "internal"
          )
        ][0],
        null,
      )
    }
  }

  _services_model_urls = {
    for service_key, service in local.services_input_targets : service_key => {
      for host, urls in {
        for route in local._services_model_routes[service_key] :
        route.host => {
          host  = route.host
          href  = route.href
          label = route.host_configured ? "website" : route.expose
          zone  = route.zone
        }...
        if route.host != null
      } : host => urls[0]
    }
  }

  services_model = {
    for service_key, service in local.services_input_targets : service_key => provider::deepmerge::mergo(
      service,
      {
        credentials = local._services_model_credentials[service_key]
        dashboard   = local._services_model_dashboards[service_key]
        key         = service_key

        fly = {
          app_name = service.target == "fly" ? local._services_model_fly_app_names[service_key] : service.fly.app_name
        }

        identity = local._services_model_identities[service_key]

        routing = merge(
          {
            for field_name, field_value in service.routing : field_name => field_value
            if field_name != "routes"
          },
          {
            backend_url = service.routing.backend_url
            container   = service.routing.container != "" ? service.routing.container : service.identity.service
            host_port   = service.routing.host_port != null ? service.routing.host_port : service.routing.backend_port
            routes      = local._services_model_routes[service_key]
          },
        )

        urls = merge(
          {
            default = {
              host  = local._services_model_url_aliases[service_key].default != null ? local._services_model_url_aliases[service_key].default.host : null
              href  = local._services_model_url_aliases[service_key].default != null ? local._services_model_url_aliases[service_key].default.href : null
              label = "default"
              zone  = null
            }
          },
          local._services_model_url_aliases[service_key].external != null ? {
            external = {
              host  = local._services_model_url_aliases[service_key].external.host
              href  = local._services_model_url_aliases[service_key].external.href
              label = "external"
              zone  = null
            }
          } : {},
          local._services_model_url_aliases[service_key].internal != null ? {
            internal = {
              host  = local._services_model_url_aliases[service_key].internal.host
              href  = local._services_model_url_aliases[service_key].internal.href
              label = "internal"
              zone  = null
            }
          } : {},
          local._services_model_urls[service_key],
        )
      },
    )
  }

  services_model_by_feature = {
    for feature in keys(local.defaults.services.features) : feature => {
      for service_key, service in local.services_model : service_key => service
      if service.features[feature]
    }
  }

  services_model_imports = {
    for service_key, service in local.services_model : service_key => service.imports.services
  }

  services_model_server_imports = {
    for service_key, service in local.services_model : service_key => service.imports.servers
  }

  services_model_x509_credentials = merge({}, [
    for service_key, service in local.services_model : {
      for credential_name, generator in service.credentials.generated :
      "${service_key}-${credential_name}" => merge(
        local.defaults.credentials.x509,
        generator,
        {
          common_name = try(generator.common_name, "${service.identity.name}-${credential_name}")
          name        = credential_name
          service_key = service_key
        },
      )
      if generator.type == "x509"
    }
  ]...)
}
