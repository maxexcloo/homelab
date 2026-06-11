locals {
  _services_render_custom_homepage_data = one([
    for svc in values(local.services_render_services) : svc.data
    if svc.identity.name == "homepage"
  ])

  _services_render_custom_homepage_server_cards = flatten([
    for server_key, server in local.servers_render_servers : [
      for card_index, dashboard_card in server.dashboard : {
        group = dashboard_card.group
        name  = dashboard_card.name
        sort  = "${length(try(dashboard_card.widgets, [])) > 0 ? "0" : "1"}:1:${server_key}:${card_index}"

        card = {
          for field, value in dashboard_card : field => value
          if(
            value != null &&
            !contains(["group", "name"], field)
          )
        }
      }
    ]
  ])

  _services_render_custom_homepage_service_cards = flatten([
    for service_key, service in local.services_render_services : [
      for card_index, dashboard_card in service.dashboard : {
        group = dashboard_card.group
        name  = dashboard_card.name
        sort  = "${length(try(dashboard_card.widgets, [])) > 0 ? "0" : "1"}:0:${service_key}:${card_index}"

        card = {
          for field, value in dashboard_card : field => value
          if(
            value != null &&
            !contains(["group", "name"], field)
          )
        }
      }
      if(
        service.identity.name != "homepage" &&
        dashboard_card.name != ""
      )
    ]
  ])

  _services_render_custom_homepage_sort_index = {
    for dashboard_card in concat(local._services_render_custom_homepage_service_cards, local._services_render_custom_homepage_server_cards) : dashboard_card.sort => dashboard_card
  }

  _services_render_custom_homepage_sorted_by_group = {
    for card in [
      for sort_key in sort(keys(local._services_render_custom_homepage_sort_index)) :
      local._services_render_custom_homepage_sort_index[sort_key]
    ] : card.group => zipmap([card.name], [card.card])...
  }

  _services_render_custom_homepage_sorted_groups = sort(distinct([
    for dashboard_card in concat(local._services_render_custom_homepage_service_cards, local._services_render_custom_homepage_server_cards) :
    dashboard_card.group
  ]))

  _services_render_custom_homepage_sorted_server_groups = [
    for group in local._services_render_custom_homepage_sorted_groups : group
    if contains([for server in values(local.servers_model) : server.identity.group], group)
  ]

  _services_render_custom_homepage_sorted_service_groups = sort(distinct([
    for group in local._services_render_custom_homepage_sorted_groups : group
    if !contains(local._services_render_custom_homepage_sorted_server_groups, group)
  ]))

  _services_render_custom_homepage_union_groups = concat(
    local._services_render_custom_homepage_sorted_service_groups,
    ["Providers"],
    local._services_render_custom_homepage_sorted_server_groups,
  )

  _services_render_custom_homepage_view = {
    layout = [
      for group in local._services_render_custom_homepage_union_groups : {
        (group) = merge(
          {
            columns = 2
            style   = "row"
            tab     = contains(local._services_render_custom_homepage_sorted_server_groups, group) ? "Servers" : "Services"
          },
          contains(local._services_render_custom_homepage_sorted_service_groups, group) ? {
            columns = local._services_render_custom_homepage_data.groups[group].columns
            style   = local._services_render_custom_homepage_data.groups[group].style
          } : {},
        )
      }
    ]

    services = [
      for group in local._services_render_custom_homepage_union_groups : {
        (group) = try(local._services_render_custom_homepage_sorted_by_group[group], [])
      }
      if group != "Providers"
    ]
  }

  services_render_custom_labels = {
    for service_key, service in local.services : service_key => {
      for container in distinct(compact([for route in service.routing.urls : route.container])) : container => merge([
        for route in service.routing.urls : {
          for label_key, label_value in merge(
            route.backend_port != null ? {
              "traefik.enable" = "true"
              "traefik.http.routers.${route.name}.entrypoints" = (
                route.expose == "cloudflare" ||
                startswith(route.expose, "proxy-")
              ) ? "web,websecure,webinternal" : "web,websecure"
              "traefik.http.routers.${route.name}.middlewares" = (
                route.expose == "internal"
                ? "internal-only@docker"
                : null
              )
              "traefik.http.routers.${route.name}.rule"    = route.host != null ? "Host(`${route.host}`)" : null
              "traefik.http.routers.${route.name}.service" = route.name
              "traefik.http.routers.${route.name}.tls.certresolver" = (
                route.expose != "cloudflare" &&
                route.https &&
                !startswith(route.expose, "proxy-")
              ) ? "cloudflare" : null
              "traefik.http.services.${route.name}.loadbalancer.server.port"   = tostring(route.backend_port)
              "traefik.http.services.${route.name}.loadbalancer.server.scheme" = route.backend_scheme == "https" ? "https" : null
            } : {},
            (
              route.backend_port != null &&
              route.expose != "cloudflare" &&
              route.https &&
              !startswith(route.expose, "proxy-")
              ) ? {
              "traefik.http.routers.${route.name}.entrypoints"      = "websecure"
              "traefik.http.routers.${route.name}-http.entrypoints" = "web"
              "traefik.http.routers.${route.name}-http.middlewares" = (
                route.expose == "internal"
                ? "internal-only@docker,redirect-to-https@docker"
                : "redirect-to-https@docker"
              )
              "traefik.http.routers.${route.name}-http.rule"    = route.host != null ? "Host(`${route.host}`)" : null
              "traefik.http.routers.${route.name}-http.service" = route.name
            } : {},
            (
              route.backend_port != null &&
              route.expose != "cloudflare" &&
              route.https &&
              !startswith(route.expose, "proxy-") &&
              route.url != null &&
              try(local.dns_render_managed_zones_by_url[route.url], null) != null
              ) ? {
              "traefik.http.routers.${route.name}.tls.domains[0].main" = route.url
            } : {},
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

  services_render_custom_service_context = {
    for service_key, service in local.services : service_key => merge(
      service.identity.name == "homepage" ? {
        homepage = local._services_render_custom_homepage_view
      } : {},
      service.identity.name != "traefik" ? {} : {
        # Port 8000 is the webinternal Traefik entrypoint on the target server.
        proxy_routes = merge(
          merge([
            for svc in values(local.services_render_services) : {
              for route in svc.routing.urls :
              route.name => {
                backend_url = "http://${local.servers_render_servers[svc.target].runtime.addresses.tailscale_ipv4}:8000"
                host        = route.host
              }
              if(
                route.proxy_server == service.target &&
                try(local.servers_render_servers[svc.target].runtime.addresses.tailscale_ipv4, "") != "" &&
                route.host != null
              )
            }
          ]...),
          merge([
            for source_server_key, source_server in local.servers_render_servers : {
              for route in source_server.routing.urls :
              "server-${source_server_key}-${substr(sha1(route.url), 0, 12)}" => {
                backend_url = route.backend_url
                host        = route.url
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
