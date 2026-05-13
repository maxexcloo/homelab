locals {
  _services_render_custom_homepage_base_servers = {
    for server_key, server in local.servers : server_key => {
      enabled = server.dashboard.enabled
      group   = local.defaults.types[server.type].label
      name    = server.dashboard.name

      card = {
        for field, value in {
          description = server.dashboard.description
          href        = server.dashboard.href
          icon        = server.dashboard.icon
          siteMonitor = server.dashboard.siteMonitor
          statusStyle = server.dashboard.siteMonitor != null ? "dot" : null
          widget      = length(server.dashboard.widget) > 0 ? yamldecode(templatestring(yamlencode(server.dashboard.widget), { server = server })) : null
        } : field => value
        if value != null
      }

      items = [
        for item in server.dashboard.items : {
          name = templatestring(tostring(item.name), { server = server })
          card = {
            for field, value in yamldecode(templatestring(yamlencode({
              description = try(item.description, null)
              href        = try(item.href, null)
              icon        = try(item.icon, null)
              siteMonitor = try(item.siteMonitor, null)
              statusStyle = try(item.siteMonitor, null) != null ? "dot" : null
              widget      = length(try(item.widget, {})) > 0 ? item.widget : null
            }), { server = server })) : field => value
            if value != null
          }
        }
      ]
    }
  }

  _services_render_custom_homepage_derived_server_groups = sort(distinct([
    for server in values(local._services_render_custom_homepage_base_servers) : server.group
  ]))

  _services_render_custom_homepage_derived_server_names = [
    for server in values(local._services_render_custom_homepage_base_servers) : server.name
  ]

  _services_render_custom_homepage_derived_service_cards = {
    for service_key, service in local._services_render_services : service_key => {
      for field, value in {
        container   = service.dashboard.container
        description = service.dashboard.description != "" ? service.dashboard.description : null
        href        = service.dashboard.href
        icon        = service.dashboard.icon
        server      = service.dashboard.container != null ? service.target : null
        siteMonitor = service.dashboard.siteMonitor
        statusStyle = service.dashboard.siteMonitor != null ? "dot" : null
        widget      = length(service.dashboard.widget) > 0 ? service.dashboard.widget : null
      } : field => value
      if value != null
    }
  }

  _services_render_custom_homepage_layout_groups_server = sort(distinct([
    for candidate_key, candidate in local._services_render_services : candidate.dashboard.group
    if candidate_key != "homepage-${candidate.target}" && candidate.dashboard.enabled && candidate.dashboard.group != "" && candidate.dashboard.name != "" && contains(local._services_render_custom_homepage_derived_server_names, candidate.dashboard.group)
  ]))

  _services_render_custom_homepage_layout_groups_service = sort(distinct([
    for candidate_key, candidate in local._services_render_services : candidate.dashboard.group
    if candidate_key != "homepage-${candidate.target}" && candidate.dashboard.enabled && candidate.dashboard.group != "" && candidate.dashboard.name != "" && !contains(local._services_render_custom_homepage_derived_server_names, candidate.dashboard.group)
  ]))

  _services_render_custom_homepage_template_data = {
    homepage = {
      layout = merge(
        {
          for group in local._services_render_custom_homepage_layout_groups_service : group => {
            columns = local.defaults.groups[group].columns
            style   = local.defaults.groups[group].style
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
          for group in local._services_render_custom_homepage_derived_server_groups : group => {
            columns = 2
            style   = "row"
            tab     = "Servers"
          }
        },
        {
          for group in local._services_render_custom_homepage_layout_groups_server : group => {
            columns = 2
            style   = "row"
            tab     = "Servers"
          }
        },
      )

      services = [
        for group in sort(distinct(concat(
          local._services_render_custom_homepage_layout_groups_server,
          local._services_render_custom_homepage_layout_groups_service,
          local._services_render_custom_homepage_derived_server_groups,
          ))) : {
          (group) = concat(
            flatten([
              for service in [
                # "0:" prefix sorts widget-bearing services before plain entries ("1:")
                # so each group renders with its widget cards at the top.
                for entry in sort([
                  for service in values(local._services_render_services) :
                  "${length(service.dashboard.widget) > 0 ? "0" : "1"}:${service.key}"
                  if service.identity.service != "homepage" && service.dashboard.enabled && service.dashboard.name != ""
                ]) : local._services_render_services[split(":", entry)[1]]
                ] : concat(
                [{
                  (service.dashboard.name) = local._services_render_custom_homepage_derived_service_cards[service.key]
                }],
                [
                  for item in service.dashboard.items : {
                    (item.name) = {
                      for field, value in {
                        description = try(item.description, null) != "" ? try(item.description, null) : null
                        href        = try(item.href, null)
                        icon        = try(item.icon, null)
                        siteMonitor = try(item.siteMonitor, null)
                        statusStyle = try(item.siteMonitor, null) != null ? "dot" : null
                        widget      = length(try(item.widget, {})) > 0 ? item.widget : null
                      } : field => value
                      if value != null
                    }
                  }
                  if try(item.name, "") != ""
                ]
              )
              if service.dashboard.group == group
            ]),
            flatten([
              for server in values(local._services_render_custom_homepage_base_servers) : concat(
                server.enabled ? [{ (server.name) = server.card }] : [],
                [for item in server.items : { (item.name) = item.card }]
              )
              if server.group == group && (server.enabled || length(server.items) > 0)
            ]),
          )
        }
      ]
    }
  }

  _services_render_custom_traefik_labels = {
    for service_key, service in local.services : service_key => {
      for k, v in merge(
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
          for url_idx, url in [
            for url in service.routing.urls : url
            if lookup(local.dns_render_zones_urls, url, null) != null
          ] :
          "traefik.http.routers.${service.identity.name}.tls.domains[${url_idx}].main" => url
        } : {},
        {
          for label_key, label_value in service.routing.labels :
          label_key => try(templatestring(tostring(label_value), local._services_render_base_context[service_key]), null)
          if label_value != null
        }
      ) : k => v
      if v != null
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
      routing_container = coalesce(service.routing.container, service.identity.service)
      routing_labels    = local._services_render_custom_traefik_labels[service_key]
    }
  }
}
