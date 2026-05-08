locals {
  _services_render_custom_homepage_base_servers = {
    for server_key, server in local.servers : server_key => {
      group = local.defaults.types[server.type].label
      name  = server.description

      card = {
        description = server.platform
        href        = server.management_url
        icon        = local.defaults.types[server.type].icon
        siteMonitor = server.management_url
      }
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
        description = service.dashboard.description != "" ? service.dashboard.description : null
        href        = service.dashboard.href
        icon        = service.dashboard.icon
        siteMonitor = service.dashboard.siteMonitor
        widget      = length(service.dashboard.widget) > 0 ? service.dashboard.widget : null
      } : field => value
      if value != null
    }
  }

  _services_render_custom_homepage_layout_groups_server = sort(distinct([
    for candidate_key, candidate in local._services_render_services : candidate.dashboard.group
    if candidate_key == candidate.key && candidate_key != "homepage-${candidate.target}" && candidate.dashboard.enabled && candidate.dashboard.group != "" && candidate.dashboard.name != "" && contains(local._services_render_custom_homepage_derived_server_names, candidate.dashboard.group)
  ]))

  _services_render_custom_homepage_layout_groups_service = sort(distinct([
    for candidate_key, candidate in local._services_render_services : candidate.dashboard.group
    if candidate_key == candidate.key && candidate_key != "homepage-${candidate.target}" && candidate.dashboard.enabled && candidate.dashboard.group != "" && candidate.dashboard.name != "" && !contains(local._services_render_custom_homepage_derived_server_names, candidate.dashboard.group)
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
            [
              for service in values(local._services_render_services) : {
                (service.dashboard.name) = local._services_render_custom_homepage_derived_service_cards[service.key]
              }
              if service.identity.service != "homepage" && service.dashboard.enabled && service.dashboard.group == group && service.dashboard.name != ""
            ],
            [
              for server in values(local._services_render_custom_homepage_base_servers) : {
                (server.name) = server.card
              }
              if server.group == group
            ],
          )
        }
      ]
    }
  }

  _services_render_custom_traefik_labels = {
    for service_key, service in local.services : service_key => merge(
      service.routing.port != null ? merge(
        {
          "traefik.enable"                                                          = "true"
          "traefik.http.routers.${service.identity.name}.entrypoints"               = service.routing.ssl ? "websecure" : "web"
          "traefik.http.services.${service.identity.name}.loadbalancer.server.port" = tostring(coalesce(service.routing.backend_port, service.routing.port))

          "traefik.http.routers.${service.identity.name}.rule" = join(" || ", concat(
            service.fqdn_internal != null ? ["Host(`${service.fqdn_internal}`)"] : [],
            service.fqdn_external != null ? ["Host(`${service.fqdn_external}`)"] : [],
            [for url in service.routing.urls : "Host(`${url}`)"],
          ))
        },
        service.routing.expose == "internal" ? {
          "traefik.http.routers.${service.identity.name}.middlewares" = "internal-only@docker"
        } : {},
        service.routing.scheme == "https" ? {
          "traefik.http.services.${service.identity.name}.loadbalancer.server.scheme" = "https"
        } : {},
        service.routing.ssl && service.routing.expose != "cloudflare" ? {
          for url_idx, url in service.routing.urls :
          "traefik.http.routers.${service.identity.name}.tls.domains[${url_idx}].main" => url
        } : {},
      ) : {},
      {
        for label_key, label_value in {
          for raw_label_key, raw_label_value in service.routing.labels :
          raw_label_key => try(
            templatestring(
              tostring(raw_label_value),
              local._services_render_base_context[service_key],
            ),
            null,
          )
          if raw_label_value != null
        } :
        label_key => label_value
        if label_value != null
      }
    )
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
