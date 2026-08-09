# Stage: resolved — template contexts and resolved service fields.
locals {
  # Services with data/dashboard/truenas fields resolved via templatestring().
  # Used as the service value in template contexts and as service inventory for
  # custom cross-service config helpers.
  services_resolved = {
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
          local.services_template_contexts[service_key],
        ),
      ),
    )
  }

  # First-pass template data for templatestring() calls on service data fields.
  # Adjacent services use model values to avoid circular dependencies and prevent
  # implicit cross-service access to runtime credentials. Explicit imports receive
  # the imported service's runtime values.
  services_template_contexts = {
    for service_key, service in local.services : service_key => {
      defaults = local.defaults
      server   = try(local.servers_resolved[service.target], null)
      service  = service

      servers = merge(
        local.servers_model,
        service.target != "fly" && can(local.servers_resolved[service.target]) ? {
          (service.target) = local.servers_resolved[service.target]
        } : {},
        {
          for alias, real_key in local.services_model_server_imports[service_key] :
          alias => local.servers_resolved[real_key]
          if can(local.servers_resolved[real_key])
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

}
