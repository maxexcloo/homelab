# Stage: render — Traefik route and redirect labels.
locals {
  _services_render_traefik_redirect_labels = {
    for service_key, service in local.services_model : service_key => {
      for route in service.routing.routes : route.name => merge([
        for redirect in route.redirects : merge(
          {
            "traefik.enable"                                                      = "true"
            "traefik.http.middlewares.${redirect.name}.redirectregex.permanent"   = "true"
            "traefik.http.middlewares.${redirect.name}.redirectregex.regex"       = "^https?://${replace(redirect.host, ".", "\\.")}"
            "traefik.http.middlewares.${redirect.name}.redirectregex.replacement" = route.href
            "traefik.http.routers.${redirect.name}.entrypoints"                   = redirect.acme ? "websecure" : "webinternal"
            "traefik.http.routers.${redirect.name}.rule"                          = "Host(`${redirect.host}`)"
            "traefik.http.routers.${redirect.name}.service"                       = "noop@internal"
            "traefik.http.routers.${redirect.name}.tls.certresolver"              = redirect.acme ? "cloudflare" : null

            "traefik.http.routers.${redirect.name}.middlewares" = (
              redirect.expose == "internal"
              ? "internal-only@docker,${redirect.name}@docker"
              : "${redirect.name}@docker"
            )
          },
          redirect.acme ? {
            "traefik.http.routers.${redirect.name}-http.entrypoints" = "web"
            "traefik.http.routers.${redirect.name}-http.rule"        = "Host(`${redirect.host}`)"
            "traefik.http.routers.${redirect.name}-http.service"     = "noop@internal"

            "traefik.http.routers.${redirect.name}-http.middlewares" = (
              redirect.expose == "internal"
              ? "internal-only@docker,${redirect.name}@docker"
              : "${redirect.name}@docker"
            )
          } : {},
          (
            redirect.acme &&
            redirect.zone != null
            ) ? {
            "traefik.http.routers.${redirect.name}.tls.domains[0].main" = redirect.host
          } : {},
        )
      ]...)
    }
  }

  _services_render_traefik_route_labels = {
    for service_key, service in local.services_model : service_key => {
      for route in service.routing.routes : route.name => merge(
        route.backend_port != null ? merge(
          {
            "traefik.enable"                                                 = "true"
            "traefik.http.routers.${route.name}.rule"                        = route.host != null ? "Host(`${route.host}`)" : null
            "traefik.http.routers.${route.name}.service"                     = route.name
            "traefik.http.routers.${route.name}.tls.certresolver"            = route.acme ? "cloudflare" : null
            "traefik.http.services.${route.name}.loadbalancer.server.port"   = tostring(route.backend_port)
            "traefik.http.services.${route.name}.loadbalancer.server.scheme" = route.backend_scheme == "https" ? "https" : null

            "traefik.http.routers.${route.name}.entrypoints" = (
              route.proxy_server != null
              ? "webinternal" : (
                route.https ? "websecure" : "web"
            ))

            "traefik.http.routers.${route.name}.middlewares" = (
              route.expose == "internal" || service.features.oidc_forward_auth
              ? join(",", concat(
                route.expose == "internal" ? ["internal-only@docker"] : [],
                service.features.oidc_forward_auth ? ["oauth2-forward-auth@docker"] : [],
              ))
              : null
            )
          },
          route.acme ? {
            "traefik.http.routers.${route.name}-http.entrypoints" = "web"
            "traefik.http.routers.${route.name}-http.middlewares" = route.expose == "internal" ? "internal-only@docker,redirect-to-https@docker" : "redirect-to-https@docker"
            "traefik.http.routers.${route.name}-http.rule"        = route.host != null ? "Host(`${route.host}`)" : null
            "traefik.http.routers.${route.name}-http.service"     = route.name
          } : {},
          (
            route.acme &&
            route.host_configured &&
            route.zone != null
            ) ? {
            "traefik.http.routers.${route.name}.tls.domains[0].main" = route.host
          } : {},
          (
            service.features.monitoring &&
            service.features.oidc_forward_auth &&
            route.host != null
            ) ? {
            "traefik.http.middlewares.${route.name}-monitoring.basicauth.headerfield"  = "X-Auth-Request-User"
            "traefik.http.middlewares.${route.name}-monitoring.basicauth.removeheader" = "true"
            "traefik.http.middlewares.${route.name}-monitoring.basicauth.users"        = "gatus:${module.credentials.hashes["${service_key}-monitoring_token"]}"
            "traefik.http.routers.${route.name}-monitoring.entrypoints"                = route.https ? "websecure" : "web"
            "traefik.http.routers.${route.name}-monitoring.rule"                       = "Host(`${route.host}`) && HeaderRegexp(`Authorization`, `^Basic `)"
            "traefik.http.routers.${route.name}-monitoring.service"                    = route.name
            "traefik.http.routers.${route.name}-monitoring.tls.certresolver"           = route.acme ? "cloudflare" : null

            "traefik.http.routers.${route.name}-monitoring.middlewares" = join(",", concat(
              route.expose == "internal" ? ["internal-only@docker"] : [],
              ["${route.name}-monitoring@docker"],
            ))
          } : {},
        ) : {},
        local._services_render_traefik_redirect_labels[service_key][route.name],
        {
          for label_key, label_value in route.labels :
          label_key => templatestring(tostring(label_value), local.services_render_context_base[service_key])
          if label_value != null
        },
      )
    }
  }

  _services_render_traefik_routing_labels = {
    for service_key, service in local.services_model : service_key => {
      for container in distinct(compact([for route in service.routing.routes : route.container])) :
      container => merge([
        for route in service.routing.routes :
        local._services_render_traefik_route_labels[service_key][route.name]
        if route.container == container
      ]...)
    }
  }
}
