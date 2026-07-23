# Stage: render — template contexts and rendered service fields.
locals {
  # First-pass template data for templatestring() calls on service data fields.
  # Adjacent services use model values to avoid circular dependencies and prevent
  # implicit cross-service access to runtime credentials. Explicit imports receive
  # the imported service's runtime values.
  services_render_context_base = {
    for service_key, service in local.services : service_key => {
      defaults = local.defaults
      server   = try(local.servers_render_servers[service.target], null)
      service  = service

      servers = merge(
        local.servers_model,
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
        {
          for alias, real_key in local.services_model_imports[service_key] :
          alias => local.services[real_key]
          if can(local.services[real_key])
        },
      )
    }
  }

  # Services with data/dashboard/truenas fields rendered via templatestring().
  # Used as the service value in template contexts and as service inventory for
  # custom cross-service render helpers.
  services_render_services = {
    for service_key, service in local.services : service_key => merge(
      service,
      jsondecode(
        templatestring(
          replace(
            jsonencode({
              dashboard = service.dashboard
              data      = service.data
              truenas   = service.truenas
            }),
            local.render_json_template_expression_pattern,
            local.render_json_template_expression_replacement,
          ),
          local.services_render_context_base[service_key],
        ),
      ),
    )
  }

  # Rendered services with runtime stripped. File templates see adjacent services
  # without credentials unless they are explicitly imported.
  services_render_services_inventory = {
    for service_key, service in local.services_render_services : service_key => {
      for field_name, field_value in service : field_name => field_value
      if field_name != "runtime"
    }
  }

  # Full context passed to templatefile() for deploy artifact files. Uses rendered
  # service values while still protecting adjacent service credentials.
  services_render_template_context = {
    for service_key, service in local.services : service_key => merge(
      local.services_render_context_base[service_key],
      {
        custom  = {}
        service = local.services_render_services[service_key]
        zones   = keys(local.dns_input)

        services = merge(
          local.services_model,
          {
            for alias, real_key in local.services_model_imports[service_key] :
            alias => local.services_render_services[real_key]
            if can(local.services_render_services[real_key])
          },
        )
      },
      local.services_render_custom_traefik_context[service_key],
      try(local.services_render_custom_homepage_context[service_key], {}),
      try(local.services_render_custom_gatus_context[service_key], {}),
    )
  }
}
