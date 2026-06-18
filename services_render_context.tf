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
      servers  = local.servers_render_servers
      service  = service

      services = merge(
        local.services_model,
        {
          for alias, real_key in local.services_model_imports[service_key] :
          alias => local.services[real_key]
          if try(local.services[real_key], null) != null
        },
      )
    }
  }

  # Services with data/dashboard/truenas fields rendered via templatestring() and
  # routing_labels injected. Used as the service value in template contexts and
  # as service inventory for Homepage and Traefik render helpers.
  services_render_services = {
    for service_key, service in local.services : service_key => merge(
      service,
      jsondecode(
        templatestring(
          jsonencode({
            dashboard = service.dashboard
            data      = service.data
            truenas   = service.truenas
          }),
          local.services_render_context_base[service_key],
        ),
      ),
      {
        routing_labels = local.services_render_routing_labels[service_key]
      },
    )
  }

  # Rendered services with runtime stripped. File templates see adjacent services
  # without credentials unless they are explicitly imported.
  services_render_services_safe = {
    for service_key, service in local.services_render_services : service_key => {
      for field_name, field_value in service : field_name => field_value if field_name != "runtime"
    }
  }

  # Full context passed to templatefile() for deploy artifact files. Uses rendered
  # service values while still protecting adjacent service credentials.
  services_render_template_context = {
    for service_key, service in local.services : service_key => merge(
      local.services_render_context_base[service_key],
      {
        custom  = try(local.services_render_service_context[service_key], {})
        service = local.services_render_services[service_key]
        zones   = keys(local.dns_input)

        services = merge(
          local.services_render_services_safe,
          {
            for alias, real_key in local.services_model_imports[service_key] :
            alias => local.services_render_services[real_key]
            if try(local.services_render_services[real_key], null) != null
          },
        )
      },
    )
  }
}
