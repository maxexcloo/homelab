locals {
  _services_config_traefik_proxy_routes = concat(
    flatten([
      for source_service in values(local.services_model) : [
        for route in source_service.routing : {
          name        = route.name
          backend_url = "http://${local.servers_resolved[source_service.target].runtime.addresses.tailscale_ipv4}:8000"
          host        = route.host
          redirect_to = null
          target      = route.proxy_server
        }
        if(
          route.proxy_server != null &&
          route.host != null
        )
      ]
    ]),
    flatten([
      for source_service in values(local.services_model) : flatten([
        for route in source_service.routing : [
          for redirect in route.redirects : {
            name        = redirect.name
            backend_url = null
            host        = redirect.host
            redirect_to = route.href
            target      = redirect.proxy_server
          }
          if(
            redirect.proxy_server != null &&
            redirect.host != null
          )
        ]
      ])
    ]),
    flatten([
      for source_server_key, source_server in local.servers_model : [
        for route in source_server.routing : {
          name        = "server-${source_server_key}-${substr(sha1(route.host), 0, 12)}"
          backend_url = route.backend_url
          host        = route.host
          redirect_to = null
          target      = contains(["external", "internal"], route.expose) ? source_server_key : trimprefix(route.expose, "proxy-")
        }
        if(
          contains(["external", "internal"], route.expose) ||
          startswith(route.expose, "proxy-")
        )
      ]
    ]),
  )

  # Redirect labels.
  _services_config_traefik_redirect_labels = {
    for service_key, service in local.services_model : service_key => {
      for route in service.routing : route.name => merge([
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

  _services_config_traefik_route_labels = {
    for service_key, service in local.services_model : service_key => {
      for route in service.routing : route.name => merge(
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
            route.backend_scheme != "" &&
            route.host != null
            ) ? {
            "traefik.http.routers.${route.name}-monitoring.entrypoints"      = route.https ? "websecure" : "web"
            "traefik.http.routers.${route.name}-monitoring.rule"             = "Host(`${route.host}`) && Header(`X-Gatus-Token`, `op://${local.defaults.onepassword.vaults.services.id}/${local.onepassword_service_item_ids[service_key]}/monitoring_token`)"
            "traefik.http.routers.${route.name}-monitoring.tls.certresolver" = route.acme ? "cloudflare" : null

            "traefik.http.routers.${route.name}-monitoring.middlewares" = route.expose == "internal" ? "internal-only@docker" : null

            "traefik.http.routers.${route.name}-monitoring.service" = try(
              templatestring(
                tostring(route.labels["traefik.http.routers.${route.name}.service"]),
                local.services_template_contexts[service_key],
              ),
              route.name,
            )
          } : {},
        ) : {},
        local._services_config_traefik_redirect_labels[service_key][route.name],
        {
          for label_key, label_value in route.labels :
          label_key => templatestring(tostring(label_value), local.services_template_contexts[service_key])
          if label_value != null
        },
      )
    }
  }

  services_config_traefik = {
    for service_key, service in local.services_model : service_key => {
      # Port 8000 is the webinternal Traefik entrypoint on the target server.
      proxy_routes = {
        for proxy_route in local._services_config_traefik_proxy_routes :
        proxy_route.name => {
          backend_url = proxy_route.backend_url
          host        = proxy_route.host
          redirect_to = proxy_route.redirect_to
        }
        if proxy_route.target == service.target
      }
    }
    if service.identity.service == "traefik"
  }

  services_config_traefik_routing_labels = {
    for service_key, service in local.services_model : service_key => {
      for container in distinct(compact([for route in service.routing : route.container])) :
      container => {
        for label_key, label_value in merge([
          for route in service.routing :
          local._services_config_traefik_route_labels[service_key][route.name]
          if route.container == container
        ]...) :
        label_key => label_value
        if label_value != null
      }
    }
  }
}
