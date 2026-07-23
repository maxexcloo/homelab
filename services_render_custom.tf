# Stage: render — service-specific cross-service aggregation.
locals {
  services_render_custom_context = {
    for service_key, service in local.services : service_key => merge(
      service.identity.name == "homepage" ? {
        homepage = local.services_render_dashboard_view
      } : {},
      !can(local.services_render_custom_traefik_services[service_key]) ? {} : {
        # Port 8000 is the webinternal Traefik entrypoint on the target server.
        proxy_routes = merge(
          merge([
            for rendered_service in values(local.services_render_services) : {
              for route in rendered_service.routing.urls :
              route.name => {
                backend_url = "http://${local.servers_render_servers[rendered_service.target].runtime.addresses.tailscale_ipv4}:8000"
                host        = route.host
                redirect_to = null
              }
              if(
                route.proxy_server == service.target &&
                try(local.servers_render_servers[rendered_service.target].runtime.addresses.tailscale_ipv4, "") != "" &&
                route.host != null
              )
            }
          ]...),
          merge([
            for rendered_service in values(local.services_render_services) : merge([
              for route in rendered_service.routing.urls : {
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

  services_render_custom_homepage_count_invalid = length([
    for service_key, service in local.services_model : service_key
    if service.identity.name == "homepage"
  ]) != 1

  services_render_custom_homepage_data = try(one([
    for service in values(local.services_render_services) : service.data
    if service.identity.name == "homepage"
  ]), {})

  # Model-only Traefik subset shared by custom rendering and validation.
  services_render_custom_traefik_services = {
    for service_key, service in local.services_model : service_key => service
    if service.identity.name == "traefik"
  }
}
