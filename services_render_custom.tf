locals {
  _homepage_cards_by_group = {
    for card in [
      for sort_key in sort(keys(local._homepage_cards_by_sort)) :
      local._homepage_cards_by_sort[sort_key]
    ] : card.group => zipmap([card.name], [card.card])...
  }

  _homepage_cards_by_sort = {
    for dashboard_card in concat(local._homepage_service_cards, local._homepage_server_cards) : dashboard_card.sort => dashboard_card
  }

  _homepage_groups = concat(
    local._homepage_service_groups,
    ["Providers"],
    local._homepage_server_groups,
  )

  _homepage_server_cards = flatten([
    for server_key, server in local.servers : [
      for card_index, dashboard_card in server.dashboard : {
        group = dashboard_card.group
        name  = dashboard_card.name
        sort  = "1:${length(try(dashboard_card.widgets, [])) > 0 ? "0" : "1"}:${server_key}:${card_index}"

        card = {
          for field, value in yamldecode(templatestring(yamlencode(dashboard_card), {
            defaults = local.defaults
            server   = server
          })) : field => value
          if value != null && !contains(["group", "name"], field)
        }
      }
    ]
  ])

  _homepage_server_groups = concat(
    local._homepage_server_matched_groups,
    [
      for group in sort(distinct([
        for dashboard_card in local._homepage_server_cards : dashboard_card.group
      ])) : group
      if !contains(local._homepage_server_matched_groups, group)
    ],
  )

  _homepage_server_matched_groups = sort(distinct([
    for dashboard_card in local._homepage_service_cards : dashboard_card.group
    if contains(local._homepage_server_names, dashboard_card.group)
  ]))

  _homepage_server_names = [
    for dashboard_card in local._homepage_server_cards : dashboard_card.name
  ]

  _homepage_service_cards = flatten([
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

  _homepage_service_groups = sort(distinct([
    for dashboard_card in local._homepage_service_cards : dashboard_card.group
    if !contains(local._homepage_server_names, dashboard_card.group)
  ]))

  _homepage_template_data = {
    homepage = {
      layout = [
        for group in local._homepage_groups : {
          (group) = (
            group == "Providers" ? {
              columns = 2
              style   = "row"
              tab     = "Services"
              } : contains(local._homepage_service_groups, group) ? {
              columns = local.services_input["homepage"].data.groups[group].columns
              style   = local.services_input["homepage"].data.groups[group].style
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
        for group in local._homepage_groups : {
          (group) = try(local._homepage_cards_by_group[group], [])
        }
        if group != "Providers"
      ]
    }
  }

  _traefik_labels = {
    for service_key, service in local.services : service_key => {
      for label_key, label_value in merge(
        service.routing.port != null ? {
          # Explicit certresolver required — without it Traefik won't proactively
          # request per-router certs at startup; first HTTPS hit fails with no cert.
          # Null for Cloudflare-exposed services; the tunnel cert covers them.
          "traefik.enable"                                                            = "true"
          "traefik.http.routers.${service.identity.name}.entrypoints"                 = service.routing.ssl ? "websecure" : "web"
          "traefik.http.routers.${service.identity.name}.middlewares"                 = service.routing.expose == "internal" ? "internal-only@docker" : null
          "traefik.http.routers.${service.identity.name}.tls.certresolver"            = service.routing.ssl && service.routing.expose != "cloudflare" ? "cloudflare" : null
          "traefik.http.services.${service.identity.name}.loadbalancer.server.port"   = tostring(coalesce(service.routing.backend_port, service.routing.port))
          "traefik.http.services.${service.identity.name}.loadbalancer.server.scheme" = service.routing.scheme == "https" ? "https" : null

          "traefik.http.routers.${service.identity.name}.rule" = join(" || ", concat(
            service.fqdn_internal != null ? ["Host(`${service.fqdn_internal}`)"] : [],
            service.fqdn_external != null ? ["Host(`${service.fqdn_external}`)"] : [],
            [for url in service.routing.urls : "Host(`${url}`)"],
          ))
        } : {},
        # Only emit tls.domains for managed DNS zones — unmanaged domains have no
        # ACME delegation record and would cause DNS-01 challenges to fail silently.
        service.routing.port != null && service.routing.ssl && service.routing.expose != "cloudflare" ? {
          for url_index, url in [
            for url in service.routing.urls : url
            if lookup(local.dns_render_zones_urls, url, null) != null
          ] :
          "traefik.http.routers.${service.identity.name}.tls.domains[${url_index}].main" => url
        } : {},
        {
          for label_key, label_value in service.routing.labels :
          label_key => try(templatestring(tostring(label_value), local.services_render_pre_template_context[service_key]), null)
          if label_value != null
        }
      ) : label_key => label_value
      if label_value != null
    }
  }

  services_render_custom_context = {
    for service_key, service in local.services : service_key =>
    lookup({
      homepage = local._homepage_template_data
    }, service.identity.name, {})
  }

  services_render_custom_service = {
    for service_key, service in local.services : service_key => {
      routing_labels = local._traefik_labels[service_key]
    }
  }
}
