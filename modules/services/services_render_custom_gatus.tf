# Stage: render — Gatus-specific global inventory.
locals {
  _services_render_custom_gatus_provider_endpoints = flatten([
    for bookmark_group in try(local.services_render_custom_homepage_data.bookmarks, []) : flatten([
      for group_name, bookmarks in bookmark_group : flatten([
        for bookmark in bookmarks : [
          for bookmark_name, bookmark_items in bookmark : {
            name  = bookmark_name
            group = group_name
            url   = one(bookmark_items).href

            alerts = [
              {
                type = "email"
              },
            ]

            conditions = [
              "[STATUS] == any(200, 401, 403)",
              "[RESPONSE_TIME] < 5000",
            ]
          }
          if try(one(bookmark_items).href, "") != ""
        ]
      ])
      if group_name == "Providers"
    ])
  ])

  services_render_custom_gatus_context = {
    for service_key, service in local.services : service_key => {
      custom = {
        gatus = {
          provider_endpoints = local._services_render_custom_gatus_provider_endpoints
        }
      }

      servers = merge(
        local.servers_model,
        local.servers_render_servers,
        service.target != "fly" && can(local.servers_render_servers[service.target]) ? {
          (service.target) = local.servers_render_servers[service.target]
        } : {},
        {
          for alias, real_key in local.services_model_server_imports[service_key] :
          alias => local.servers_render_servers[real_key]
          if can(local.servers_render_servers[real_key])
        },
      )

      services = merge(
        local.services_model,
        local.services_render_services_inventory,
        {
          for monitored_service_key, monitored_service in local.services_render_services :
          monitored_service_key => merge(
            local.services_render_services_inventory[monitored_service_key],
            {
              runtime = {
                credentials = {
                  monitoring_token = monitored_service.runtime.credentials.monitoring_token
                }
              }
            },
          )
          if(
            monitored_service.features.monitoring &&
            monitored_service.routing.backend_scheme != ""
          )
        },
        {
          for alias, real_key in local.services_model_imports[service_key] :
          alias => local.services_render_services[real_key]
          if can(local.services_render_services[real_key])
        },
      )
    }
    if service.identity.name == "gatus"
  }
}
