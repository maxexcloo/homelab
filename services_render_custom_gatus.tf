# Stage: render — Gatus-specific global inventory.
locals {
  services_render_custom_gatus_context = {
    for service_key, service in local.services : service_key => {
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
          for alias, real_key in local.services_model_imports[service_key] :
          alias => local.services_render_services[real_key]
          if can(local.services_render_services[real_key])
        },
      )
    }
    if service.identity.name == "gatus"
  }
}
