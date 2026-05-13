locals {
  # Only .tftpl files are rendered; the suffix is stripped from the deployed path.
  # Other files use filebase64(), so static and binary assets share one path.
  _services_render_file_inputs = flatten([
    for service_key, service in local.services : [
      for file_path in fileset(path.module, "templates/services/${service.identity.service}/**") : {
        path            = "${path.module}/${file_path}"
        raw_encrypt     = endswith(trimsuffix(file_path, ".tftpl"), ".raw")
        rel_path        = trimsuffix(trimsuffix(trimprefix(file_path, "templates/services/${service.identity.service}/"), ".tftpl"), ".raw")
        render_template = endswith(file_path, ".tftpl")
        stack           = service_key
        target          = service.target
      }
      # These two files are handled by platform-specific renderers (TrueNAS catalog
      # apps and Komodo/Fly compose) rather than generic sidecars.
      if !contains(["app.json.tftpl", "docker-compose.yaml.tftpl"], basename(file_path))
      && service.deploy
    ]
  ])

  _services_render_files_compose_raw = {
    for service_key, service in local.services : service_key => yamldecode(
      templatefile(
        "${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl",
        local.services_render_context[service_key],
      ),
    )
    if service.deploy && fileexists("${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl")
  }

  _services_render_rendered_services_no_state = {
    for service_key, service in local.services_render_services : service_key => {
      for k, v in service : k => v if k != "state"
    }
  }

  _services_render_services_no_state = {
    for service_key, service in local.services : service_key => {
      for k, v in service : k => v if k != "state"
    }
  }

  # Pre-render context with imported services overlaid. References local.services
  # rather than services_render_services so dashboard and data strings can be
  # template-rendered from this context without circularity.
  services_render_base_context = {
    for service_key, service in local.services : service_key => {
      defaults = local.defaults
      server   = try(local.servers[service.target], null)
      servers  = local.servers
      service  = service

      services = merge(
        local._services_render_services_no_state,
        {
          for alias, real_key in local.services_model_imports[service_key] :
          alias => local.services[real_key]
          if contains(keys(local.services), real_key)
        },
      )
    }
  }

  # Final template context for compose/sidecar renders. Imported service aliases
  # are overlaid here so templates can reference `services.<alias>`.
  services_render_context = {
    for service_key, service in local.services : service_key => merge(
      local.services_render_base_context[service_key],
      {
        custom  = lookup(local.services_render_custom_context, service_key, {})
        service = local.services_render_services[service_key]

        services = merge(
          local._services_render_rendered_services_no_state,
          {
            for alias, real_key in local.services_model_imports[service_key] :
            alias => local.services_render_services[real_key]
            if contains(keys(local.services_render_services), real_key)
          },
        )
      },
    )
  }

  # Rendered Docker Compose content keyed by expanded service stack.
  services_render_files_compose = {
    for service_key, compose in local._services_render_files_compose_raw : service_key => yamlencode(
      merge(
        compose,
        {
          services = {
            for compose_service_key, compose_service in compose.services : compose_service_key => merge(
              compose_service,
              compose_service_key == local.services_render_services[service_key].routing.container && length(local.services_render_services[service_key].routing_labels) > 0 ? {
                labels = merge(
                  lookup(compose_service, "labels", {}),
                  local.services_render_services[service_key].routing_labels,
                )
              } : {},
            )
          }
        },
      )
    )
  }

  # Deployed sidecar files include encrypted content metadata used by Fly,
  # Komodo, and TrueNAS GitHub repository file resources.
  services_render_files_sidecars = {
    for file_input in local._services_render_file_inputs : "${file_input.stack}/${file_input.rel_path}" => merge(
      file_input,
      {
        content_base64 = (
          file_input.render_template
          ? base64encode(
            templatefile(
              file_input.path,
              local.services_render_context[file_input.stack],
            ),
          )
          : filebase64(file_input.path)
        )
        content_type = (
          file_input.raw_encrypt
          ? "binary"
          : lookup(
            {
              ".env"  = "dotenv"
              ".json" = "json"
              ".yaml" = "yaml"
              ".yml"  = "yaml"
            },
            try(regex("\\.[^.]+$", lower(file_input.rel_path)), ""),
            "binary",
          )
        )
      }
    )
  }

  # Render-time service inventory: dashboard/data strings template-rendered,
  # routing_labels merged in from services_render_custom_service.
  services_render_services = {
    for service_key, service in local.services : service_key => merge(
      service,
      jsondecode(
        templatestring(
          jsonencode({
            dashboard = service.dashboard
            data      = service.data
          }),
          local.services_render_base_context[service_key],
        ),
      ),
      lookup(local.services_render_custom_service, service_key, {}),
    )
  }
}
