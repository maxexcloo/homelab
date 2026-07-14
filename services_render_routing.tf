# Stage: render — routing labels and proxy route context.
locals {
  services_render_routing_labels = {
    for service_key, service in local.services : service_key => {
      for container in distinct(compact([for route in service.routing.urls : route.container])) : container => merge([
        for route in service.routing.urls : {
          for label_key, label_value in merge(
            route.backend_port != null ? merge(
              {
                "traefik.enable"                                                 = "true"
                "traefik.http.routers.${route.name}.middlewares"                 = route.expose == "internal" ? "internal-only@docker" : null
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
              },
              route.acme ? {
                "traefik.http.routers.${route.name}-http.entrypoints" = "web"
                "traefik.http.routers.${route.name}-http.middlewares" = route.expose == "internal" ? "internal-only@docker,redirect-to-https@docker" : "redirect-to-https@docker"
                "traefik.http.routers.${route.name}-http.rule"        = route.host != null ? "Host(`${route.host}`)" : null
                "traefik.http.routers.${route.name}-http.service"     = route.name
              } : {},
              (
                route.acme &&
                route.url != null &&
                route.zone != null
                ) ? {
                "traefik.http.routers.${route.name}.tls.domains[0].main" = route.url
              } : {},
            ) : {},
            merge([
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
            ]...),
            {
              for label_key, label_value in route.labels :
              label_key => try(templatestring(tostring(label_value), local.services_render_context_base[service_key]), null)
              if label_value != null
            },
          ) : label_key => label_value
          if label_value != null
        }
        if route.container == container
      ]...)
    }
  }

  # Model-only Traefik service subset shared by rendering and validation.
  services_render_routing_traefik_services = {
    for service_key, service in local.services_model : service_key => service
    if service.identity.name == "traefik"
  }

  services_render_service_context = {
    for service_key, service in local.services : service_key => merge(
      service.identity.name == "homepage" ? {
        homepage = local.services_render_dashboard_view
      } : {},
      !can(local.services_render_routing_traefik_services[service_key]) ? {} : {
        # Port 8000 is the webinternal Traefik entrypoint on the target server.
        proxy_routes = merge(
          merge([
            for svc in values(local.services_render_services) : {
              for route in svc.routing.urls :
              route.name => {
                backend_url = "http://${local.servers_render_servers[svc.target].runtime.addresses.tailscale_ipv4}:8000"
                host        = route.host
                redirect_to = null
              }
              if(
                route.proxy_server == service.target &&
                try(local.servers_render_servers[svc.target].runtime.addresses.tailscale_ipv4, "") != "" &&
                route.host != null
              )
            }
          ]...),
          merge([
            for svc in values(local.services_render_services) : merge([
              for route in svc.routing.urls : {
                for redirect in route.redirects :
                redirect.name => {
                  backend_url = null
                  host        = redirect.host
                  redirect_to = route.href
                }
                if(
                  redirect.proxy_server == service.target &&
                  redirect.host != null
                )
              }
            ]...)
          ]...),
          merge([
            for source_server_key, source_server in local.servers_render_servers : {
              for route in source_server.routing.urls :
              "server-${source_server_key}-${substr(sha1(route.url), 0, 12)}" => {
                backend_url = route.backend_url
                host        = route.url
                redirect_to = null
              }
              if(
                (
                  contains(["external", "internal"], route.expose) &&
                  source_server_key == service.target
                ) ||
                route.expose == "proxy-${service.target}"
              )
            }
          ]...),
        )
      },
    )
  }
}
