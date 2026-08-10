# Stage: model — adds deterministic computed fields. No provider values; safe for for_each keys.
locals {
  # Credential field shape for each service. Runtime values are added in services_runtime.tf.
  _services_model_credentials = {
    for service_key, service in local.services_input_targets : service_key => {
      generated = local._services_model_generated_credentials[service_key]

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
        can(local._services_model_urls[service_key].default) ? {
          href        = local._services_model_urls[service_key].default.href
          siteMonitor = local._services_model_urls[service_key].default.href
        } : {},
        card,
      )
    ]
  }

  # Fly requires stable app names before generated hostnames are computed.
  _services_model_fly_app_names = {
    for service_key, service in local.services_input_targets : service_key =>
    service.fly.app_name != "" ? service.fly.app_name : "${local.defaults.organisation.name}-${service.identity.name}"
  }

  _services_model_generated_credentials = {
    for service_key, service in local.services_input_targets : service_key => merge(
      service.credentials.generated,
      (
        service.features.monitoring &&
        anytrue([for route in values(service.routing) : try(route.backend.port, null) != null])
        ) ? {
        monitoring_token = {
          length = 32
          type   = "hex"
        }
      } : {},
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

  _services_model_route_defaults = {
    container = ""
    https     = true
    labels    = {}
    redirects = []
  }

  _services_model_route_inputs = {
    for service_key, service in local.services_input_targets : service_key => {
      for route_id, route in service.routing : route_id => merge(
        local._services_model_route_defaults,
        route,
        {
          id              = route_id
          host_configured = route.host != null
          path            = try(route.path, "")
          proxy_server    = startswith(route.expose, "proxy-") ? trimprefix(route.expose, "proxy-") : null

          backend = {
            port           = try(route.backend.port, null)
            published_port = try(route.backend.published_port, null) != null ? route.backend.published_port : try(route.backend.port, null)
            scheme         = try(route.backend.scheme, "") != "" ? route.backend.scheme : try(route.backend.port, null) != null ? "http" : ""
          }

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
              (try(route.backend.scheme, "") != "" || try(route.backend.port, null) != null)
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
              zone         = try(local.dns_model_managed_zones_by_host[redirect], null)

              acme = (
                try(route.https, true) &&
                !startswith(route.expose, "proxy-")
              )
            }
          ]
        },
      )
    }
  }

  _services_model_routes = {
    for service_key, service in local.services_input_targets : service_key => {
      for route_id, route in local._services_model_route_inputs[service_key] : route_id => merge(
        route,
        {
          container = route.container != "" ? route.container : service.identity.service
          host      = route.host_configured ? route.host : route.dns_target_host
          name      = route.id == "default" ? service.identity.name : "${service.identity.name}-${route.id}"

          acme = (
            route.https &&
            route.proxy_server == null
          )

          href = (
            route.host_configured ||
            route.dns_target_host != null
          ) ? "${route.https ? "https" : "http"}://${route.host_configured ? route.host : route.dns_target_host}${route.path}" : null

          zone = (
            route.dns_target_host == null &&
            !route.host_configured
            ) ? null : (
            route.host_configured ? local.dns_model_managed_zones_by_host[route.host]
            : service.target == "fly" ? "fly.dev"
            : route.expose == "internal" ? local.defaults.domains.internal
            : local.defaults.domains.external
          )
        },
      )
    }
  }

  _services_model_target_servers = {
    for service_key, service in local.services_input_targets : service_key => try(local.servers_model[service.target], null)
  }

  _services_model_urls = {
    for service_key, service in local.services_input_targets : service_key => {
      for route_id, route in local._services_model_routes[service_key] : route_id => {
        host  = route.host
        href  = route.href
        label = route_id
        zone  = route.zone
      }
      if route.host != null
    }
  }

  services_model = {
    for service_key, service in local.services_input_targets : service_key => merge(
      service,
      {
        dashboard = local._services_model_dashboards[service_key]
        identity  = local._services_model_identities[service_key]
        key       = service_key
        routing   = local._services_model_routes[service_key]
        urls      = local._services_model_urls[service_key]

        credentials = merge(
          service.credentials,
          local._services_model_credentials[service_key],
        )

        fly = merge(
          service.fly,
          {
            app_name = service.target == "fly" ? local._services_model_fly_app_names[service_key] : service.fly.app_name
          },
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
