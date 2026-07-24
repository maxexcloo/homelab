# Stage: render — Traefik-specific proxy aggregation.
locals {
  _services_render_custom_traefik_proxy_routes = concat(
    flatten([
      for source_service in values(local.services_model) : [
        for route in source_service.routing.routes : {
          name        = route.name
          backend_url = "http://${local.servers_render_servers[source_service.target].runtime.addresses.tailscale_ipv4}:8000"
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
        for route in source_service.routing.routes : [
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
        for route in source_server.routing.routes : {
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

  services_render_custom_traefik_context = {
    for service_key, service in local.services_model : service_key => merge(
      {
        routing_labels = local._services_render_traefik_routing_labels[service_key]
      },
      service.identity.name == "traefik" ? {
        custom = {
          # Port 8000 is the webinternal Traefik entrypoint on the target server.
          proxy_routes = {
            for proxy_route in local._services_render_custom_traefik_proxy_routes :
            proxy_route.name => {
              backend_url = proxy_route.backend_url
              host        = proxy_route.host
              redirect_to = proxy_route.redirect_to
            }
            if proxy_route.target == service.target
          }
        }
      } : {},
    )
  }
}
