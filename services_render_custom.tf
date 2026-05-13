locals {
  _services_render_custom_homepage_cards_by_group = {
    for card in [
      for sort_key in sort(keys(local._services_render_custom_homepage_cards_by_sort)) :
      local._services_render_custom_homepage_cards_by_sort[sort_key]
    ] : card.group => zipmap([card.name], [card.card])...
  }

  _services_render_custom_homepage_cards_by_sort = {
    for dashboard_card in concat(local._services_render_custom_homepage_service_cards, local._services_render_custom_homepage_server_cards) : dashboard_card.sort => dashboard_card
  }

  _services_render_custom_homepage_server_cards = flatten([
    for server_key, server in local.servers : [
      for card_index, dashboard_card in server.dashboard : {
        group = dashboard_card.group
        name  = dashboard_card.name
        sort  = "1:${length(dashboard_card.widgets) > 0 ? "0" : "1"}:${server_key}:${card_index}"

        card = {
          for field, value in yamldecode(templatestring(yamlencode({
            description = dashboard_card.description
            href        = dashboard_card.href
            icon        = dashboard_card.icon
            siteMonitor = dashboard_card.siteMonitor
            widgets     = length(dashboard_card.widgets) > 0 ? dashboard_card.widgets : null
          }), { server = server })) : field => value
          if value != null
        }
      }
    ]
  ])

  _services_render_custom_homepage_server_group_order = concat(
    local._services_render_custom_homepage_server_name_groups,
    [
      for group in sort(distinct([
        for dashboard_card in local._services_render_custom_homepage_server_cards : dashboard_card.group
      ])) : group
      if !contains(local._services_render_custom_homepage_server_name_groups, group)
    ],
  )

  _services_render_custom_homepage_server_name_groups = sort(distinct([
    for dashboard_card in local._services_render_custom_homepage_service_cards : dashboard_card.group
    if contains(local._services_render_custom_homepage_server_names, dashboard_card.group)
  ]))

  _services_render_custom_homepage_server_names = [
    for dashboard_card in local._services_render_custom_homepage_server_cards : dashboard_card.name
  ]

  _services_render_custom_homepage_service_cards = flatten([
    for service_key, service in local.services_render_services : [
      for card_index, dashboard_card in service.dashboard : {
        group = dashboard_card.group == try(local.servers[service.target].description, null) ? local.servers[service.target].dashboard[0].name : dashboard_card.group
        name  = dashboard_card.name
        sort  = "0:${length(dashboard_card.widgets) > 0 ? "0" : "1"}:${service_key}:${card_index}"

        card = {
          for field, value in {
            container   = dashboard_card.container
            description = dashboard_card.description != "" ? dashboard_card.description : null
            href        = dashboard_card.href
            icon        = dashboard_card.icon
            server      = dashboard_card.container != null ? service.target : null
            siteMonitor = dashboard_card.siteMonitor
            widgets     = length(dashboard_card.widgets) > 0 ? dashboard_card.widgets : null
          } : field => value
          if value != null
        }
      }
      if service.identity.service != "homepage" && dashboard_card.name != ""
    ]
  ])

  _services_render_custom_homepage_service_group_order = sort(distinct([
    for dashboard_card in local._services_render_custom_homepage_service_cards : dashboard_card.group
    if !contains(local._services_render_custom_homepage_server_names, dashboard_card.group)
  ]))

  _services_render_custom_homepage_template_data = {
    homepage = {
      layout = merge(
        {
          for group in local._services_render_custom_homepage_service_group_order : group => {
            columns = local.services_input["homepage"].data.groups[group].columns
            style   = local.services_input["homepage"].data.groups[group].style
            tab     = "Services"
          }
        },
        {
          Providers = {
            columns = 2
            style   = "row"
            tab     = "Services"
          }
        },
        {
          for group in local._services_render_custom_homepage_server_group_order : group => {
            columns = 2
            style   = "row"
            tab     = "Servers"
          }
        },
      )

      services = [
        for group in concat(
          local._services_render_custom_homepage_service_group_order,
          local._services_render_custom_homepage_server_group_order,
          ) : {
          (group) = try(local._services_render_custom_homepage_cards_by_group[group], [])
        }
      ]
    }
  }

  _services_render_custom_traefik_labels = {
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
          label_key => try(templatestring(tostring(label_value), local.services_render_base_context[service_key]), null)
          if label_value != null
        }
      ) : label_key => label_value
      if label_value != null
    }
  }

  services_render_custom_context = {
    for service_key, service in local.services : service_key =>
    lookup({
      homepage = local._services_render_custom_homepage_template_data
    }, service.identity.service, {})
  }

  services_render_custom_service = {
    for service_key, service in local.services : service_key => {
      routing_labels = local._services_render_custom_traefik_labels[service_key]
    }
  }
}
