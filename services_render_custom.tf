locals {
  _custom_homepage_cards_by_group = {
    for card in [
      for sort_key in sort(keys(local._custom_homepage_cards_by_sort)) :
      local._custom_homepage_cards_by_sort[sort_key]
    ] : card.group => zipmap([card.name], [card.card])...
  }

  _custom_homepage_cards_by_sort = {
    for dashboard_card in concat(local._custom_homepage_service_cards, local._custom_homepage_server_cards) : dashboard_card.sort => dashboard_card
  }

  _custom_homepage_data = [for svc in values(local.services_render_services) : svc.data if svc.identity.name == "homepage"][0]

  _custom_homepage_groups = concat(
    local._custom_homepage_service_groups,
    ["Providers"],
    local._custom_homepage_server_groups,
  )

  _custom_homepage_server_cards = flatten([
    for server_key, server in local.servers_render_runtime : [
      for card_index, dashboard_card in server.dashboard : {
        group = dashboard_card.group
        name  = dashboard_card.name
        sort  = "1:${length(try(dashboard_card.widgets, [])) > 0 ? "0" : "1"}:${server_key}:${card_index}"

        card = {
          for field, value in dashboard_card : field => value
          if value != null && !contains(["group", "name"], field)
        }
      }
    ]
  ])

  _custom_homepage_server_groups = concat(
    local._custom_homepage_server_matched_groups,
    [
      for group in sort(distinct([
        for dashboard_card in local._custom_homepage_server_cards : dashboard_card.group
      ])) : group
      if !contains(local._custom_homepage_server_matched_groups, group)
    ],
  )

  _custom_homepage_server_matched_groups = sort(distinct([
    for dashboard_card in local._custom_homepage_service_cards : dashboard_card.group
    if contains(local._custom_homepage_server_names, dashboard_card.group)
  ]))

  _custom_homepage_server_names = [
    for dashboard_card in local._custom_homepage_server_cards : dashboard_card.name
  ]

  _custom_homepage_service_cards = flatten([
    for service_key, service in local.services_render_services : [
      for card_index, dashboard_card in service.dashboard : {
        group = dashboard_card.group
        name  = dashboard_card.name
        sort  = "0:${length(try(dashboard_card.widgets, [])) > 0 ? "0" : "1"}:${service_key}:${card_index}"

        card = {
          for field, value in dashboard_card : field => value
          if value != null && !contains(["group", "name"], field)
        }
      }
      if service.identity.name != "homepage" && dashboard_card.name != ""
    ]
  ])

  _custom_homepage_service_groups = sort(distinct([
    for dashboard_card in local._custom_homepage_service_cards : dashboard_card.group
    if !contains(local._custom_homepage_server_names, dashboard_card.group)
  ]))

  _custom_homepage = {
    layout = [
      for group in local._custom_homepage_groups : {
        (group) = (
          group == "Providers" ? {
            columns = 2
            style   = "row"
            tab     = "Services"
            } : contains(local._custom_homepage_service_groups, group) ? {
            columns = local._custom_homepage_data.groups[group].columns
            style   = local._custom_homepage_data.groups[group].style
            tab     = "Services"
            } : {
            columns = 2
            style   = "row"
            tab     = "Servers"
          }
        )
      }
    ]

    services = [
      for group in local._custom_homepage_groups : {
        (group) = try(local._custom_homepage_cards_by_group[group], [])
      }
      if group != "Providers"
    ]
  }

  services_render_custom_context = {
    for service_key, service in local.services : service_key => merge(
      service.identity.name == "homepage" ? {
        homepage = local._custom_homepage
      } : {},
      service.identity.name != "traefik" ? {} : {
        proxy_routes = {
          for svc in values(local.services_render_services) :
          svc.identity.name => {
            backend_url = "http://${local.servers_render_runtime[svc.target].runtime.addresses.tailscale_ipv4}:8080"
            host        = svc.urls.default.host
          }
          if svc.routing.expose != null &&
          startswith(svc.routing.expose, "proxy-") &&
          trimprefix(svc.routing.expose, "proxy-") == service.target &&
          try(local.servers_render_runtime[svc.target].runtime.addresses.tailscale_ipv4, null) != null &&
          svc.urls.default.host != null
        }
      },
    )
  }

  services_render_custom_labels = {
    for service_key, service in local.services : service_key => {
      for label_key, label_value in merge(
        service.routing.port != null ? {
          "traefik.enable"                                                            = "true"
          "traefik.http.routers.${service.identity.name}.middlewares"                 = service.routing.expose == "internal" ? "internal-only@docker" : null
          "traefik.http.routers.${service.identity.name}.tls.certresolver"            = service.routing.ssl && service.routing.expose != "cloudflare" && (service.routing.expose == null || !startswith(service.routing.expose, "proxy-")) ? "cloudflare" : null
          "traefik.http.services.${service.identity.name}.loadbalancer.server.port"   = tostring(coalesce(service.routing.backend_port, service.routing.port))
          "traefik.http.services.${service.identity.name}.loadbalancer.server.scheme" = service.routing.scheme == "https" ? "https" : null

          "traefik.http.routers.${service.identity.name}.entrypoints" = (
            service.routing.expose == "cloudflare" || (service.routing.expose != null && startswith(service.routing.expose, "proxy-"))
            ? (service.routing.ssl ? "websecure,webinternal" : "web,webinternal")
            : service.routing.ssl ? "websecure" : "web"
          )

          "traefik.http.routers.${service.identity.name}.rule" = join(" || ", [
            for host in distinct([
              for url_key, url in service.urls : url.host
              if url_key != "default" && url.host != null && url.host != ""
            ]) : "Host(`${host}`)"
          ])
        } : {},
        service.routing.port != null && service.routing.ssl && service.routing.expose != "cloudflare" && (service.routing.expose == null || !startswith(service.routing.expose, "proxy-")) ? {
          for url_index, url in [
            for url in service.routing.urls : url
            if lookup(local.dns_render_managed_zones_by_url, url, null) != null
          ] :
          "traefik.http.routers.${service.identity.name}.tls.domains[${url_index}].main" => url
        } : {},
        {
          for label_key, label_value in service.routing.labels :
          label_key => try(templatestring(tostring(label_value), local._services_render_context_base[service_key]), null)
          if label_value != null
        }
      ) : label_key => label_value
      if label_value != null
    }
  }
}
