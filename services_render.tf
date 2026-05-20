# Stage: render — templates, routing labels, and deploy file content.
locals {
  # Sidecar file inventory discovered from templates/services/**/. Platform-specific
  # entry points (app.json.tftpl, docker-compose.yaml.tftpl) are handled by their
  # respective platform deployers and excluded here.
  _services_render_file_inputs = flatten([
    for service_key, service in {
      for service_key, service in local.services : service_key => service
      if service.identity.service != null
      } : [
      for file_path in fileset(path.module, "templates/services/${service.identity.service}/**") : {
        path            = "${path.module}/${file_path}"
        raw_encrypt     = endswith(trimsuffix(file_path, ".tftpl"), ".raw")
        rel_path        = trimsuffix(trimsuffix(trimprefix(file_path, "templates/services/${service.identity.service}/"), ".tftpl"), ".raw")
        render_template = endswith(file_path, ".tftpl")
        stack           = service_key
        target          = service.target
      }
      # Platform renderers handle app.json.tftpl and docker-compose.yaml.tftpl.
      if !contains(["app.json.tftpl", "docker-compose.yaml.tftpl"], basename(file_path))
    ]
  ])

  # Parsed compose YAML before routing label injection. Kept separate so
  # services_render_files_compose can merge labels into the parsed structure.
  _services_render_files_compose_raw = {
    for service_key, service in local.services : service_key => yamldecode(
      templatefile(
        "${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl",
        local.services_render_template_context[service_key],
      ),
    )
    if(
      service.identity.service != null &&
      fileexists("${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl") &&
      (
        try(local.truenas_input_servers[service.target], null) != null ||
        (
          try(local.servers_model[service.target], null) != null &&
          local.servers_model[service.target].features.docker
        )
      )
    )
  }

  # Rendered services with runtime stripped. Used in services_render_template_context
  # for the same reason — file templates see adjacent services without their credentials.
  _services_render_rendered_services_safe = {
    for service_key, service in local.services_render_services : service_key => {
      for field_name, field_value in service : field_name => field_value if field_name != "runtime"
    }
  }

  # Services with runtime stripped. Used in services_render_context_base so that
  # cross-service references in templatestring() calls cannot access other services'
  # credentials.
  _services_render_services_safe = {
    for service_key, service in local.services : service_key => {
      for field_name, field_value in service : field_name => field_value if field_name != "runtime"
    }
  }

  # First-pass context for templatestring() calls on service.data and service.dashboard.
  # Uses _services_render_services_safe (runtime stripped) to avoid circular
  # dependencies — services reference each other during rendering, so each service's
  # context must use the pre-render values of adjacent services.
  services_render_context_base = {
    for service_key, service in local.services : service_key => {
      defaults = local.defaults
      server   = try(local.servers_render_runtime[service.target], null)
      servers  = local.servers_render_runtime
      service  = service

      services = merge(
        local._services_render_services_safe,
        {
          for alias, real_key in local.services_model_imports[service_key] :
          alias => local.services[real_key]
          if try(local.services[real_key], null) != null
        },
      )
    }
  }

  # Compose files with routing labels injected into the primary container's label map.
  services_render_files_compose = {
    for service_key, compose in local._services_render_files_compose_raw : service_key => yamlencode(
      merge(
        compose,
        {
          services = {
            for compose_service_key, compose_service in compose.services : compose_service_key => merge(
              compose_service,
              (
                compose_service_key == local.services_render_services[service_key].routing.container &&
                length(local.services_render_services[service_key].routing_labels) > 0
                ) ? {
                labels = merge(
                  try(compose_service.labels, {}),
                  local.services_render_services[service_key].routing_labels,
                )
              } : {},
            )
          }
        },
      )
    )
  }

  # Sidecar files (env files, configs, etc.) with rendered content and SOPS content type.
  services_render_files_sidecars = {
    for file_input in local._services_render_file_inputs : "${file_input.stack}/${file_input.rel_path}" => merge(
      file_input,
      {
        content_base64 = (
          file_input.render_template
          ? base64encode(
            templatefile(
              file_input.path,
              local.services_render_template_context[file_input.stack],
            ),
          )
          : filebase64(file_input.path)
        )
        content_type = (
          file_input.raw_encrypt
          ? "binary"
          : try(
            {
              ".env"  = "dotenv"
              ".json" = "json"
              ".yaml" = "yaml"
              ".yml"  = "yaml"
            }[try(regex("\\.[^.]+$", lower(file_input.rel_path)), "")],
            "binary",
          )
        )
      }
    )
  }

  # Services with data/dashboard/truenas fields rendered via templatestring() and
  # routing_labels injected. Used as the service value in services_render_template_context
  # and as the service inventory in services_render_custom.tf.
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
        routing_labels = local.services_render_custom_labels[service_key]
      },
    )
  }

  # Full context passed to templatefile() for deploy artifact files. Uses rendered
  # services (_services_render_rendered_services_safe) so templates see final data
  # values while still being protected from adjacent services' credentials.
  services_render_template_context = {
    for service_key, service in local.services : service_key => merge(
      local.services_render_context_base[service_key],
      {
        custom  = try(local.services_render_custom_context[service_key], {})
        service = local.services_render_services[service_key]

        services = merge(
          local._services_render_rendered_services_safe,
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
