locals {
  # Arbitrary JSON data is encoded first so templates can interpolate strings
  # anywhere in the tree without losing the original JSON shape.
  _services_render_dashboard = {
    for service_key, service in local.services : service_key => jsondecode(templatestring(
      jsonencode(service.dashboard),
      local._services_render_base_context[service_key],
    ))
  }

  # Arbitrary JSON data is encoded first so templates can interpolate strings
  # anywhere in the tree without losing the original JSON shape.
  _services_render_data = {
    for service_key, service in local.services : service_key => jsondecode(templatestring(
      jsonencode(service.data),
      local._services_render_base_context[service_key],
    ))
  }

  # File extension -> SOPS input type. Files named *.raw or *.raw.tftpl are
  # encrypted as binary and deployed without the .raw suffix for exact decrypts.
  _services_render_file_content_types = {
    ".env"  = "dotenv"
    ".json" = "json"
    ".yaml" = "yaml"
    ".yml"  = "yaml"
  }

  # Only .tftpl files are rendered; the suffix is stripped from the deployed path.
  # Other files use filebase64(), so static and binary assets share one path.
  _services_render_file_inputs = flatten([
    for service_key, service in local.services : [
      for file_path in fileset(path.module, "templates/services/${service.identity.service}/**") : merge(
        local._services_render_file_path_info[file_path],
        {
          path   = "${path.module}/${file_path}"
          stack  = service_key
          target = service.target
        }
      )
      # These two files are handled by platform-specific renderers (TrueNAS catalog
      # apps and Komodo/Fly compose) rather than generic sidecars.
      if !contains(["app.json.tftpl", "docker-compose.yaml.tftpl"], basename(file_path))
    ]
  ])

  # Pre-computed path metadata for every file under templates/services/* so the sidecar
  # loop only adds deployment context (stack key and target).
  _services_render_file_path_info = {
    for file_path in fileset(path.module, "templates/services/*/**") : file_path => {
      raw_encrypt     = endswith(trimsuffix(file_path, ".tftpl"), ".raw")
      rel_path        = trimsuffix(trimsuffix(trimprefix(file_path, "templates/services/${split("/", file_path)[2]}/"), ".tftpl"), ".raw")
      render_template = endswith(file_path, ".tftpl")
    }
  }

  _services_render_files_compose_raw = {
    for service_key, service in local.services : service_key => yamldecode(templatefile(
      "${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl",
      local.services_render_context[service_key]
    ))
    if fileexists("${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl")
  }

  # Pre-render context with import aliases overlaid. It intentionally excludes
  # rendered data/dashboard/routing values because those strings are rendered
  # from this context.
  _services_render_base_context = {
    for service_key, service in local.services : service_key => {
      defaults = local.defaults
      server   = try(local.servers[service.target], null)
      servers  = local.servers
      service  = service
      services = merge(
        local.services,
        {
          for alias, real_key in local.services_model_imports[service_key] :
          alias => local.services[real_key]
          if contains(keys(local.services), real_key)
        },
      )
    }
  }

  _services_render_routing = {
    for service_key, service in local.services : service_key => {
      container = coalesce(
        service.routing.container,
        service.identity.service,
      )

      labels = merge(
        service.routing.port != null ? merge(
          {
            "traefik.enable"                                                          = "true"
            "traefik.http.routers.${service.identity.name}.entrypoints"               = service.routing.ssl ? "websecure" : "web"
            "traefik.http.services.${service.identity.name}.loadbalancer.server.port" = tostring(service.routing.port)

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
            raw_label_key => try(templatestring(tostring(raw_label_value), local._services_render_base_context[service_key]), null)
            if raw_label_value != null
          } :
          label_key => label_value
          if label_value != null
        },
      )
    }
  }

  # Render-time service inventory with derived dashboard/data/routing values.
  # This keeps the final context from repeating the same merge for every alias.
  _services_render_services = {
    for service_key, service in local.services : service_key => merge(service, {
      data              = local._services_render_data[service_key]
      routing_container = local._services_render_routing[service_key].container
      routing_labels    = local._services_render_routing[service_key].labels

      dashboard = local._services_render_dashboard[service_key]
    })
  }

  # Final template context for compose/sidecar renders. Imported service aliases
  # are overlaid here so templates can reference `services.<alias>`.
  services_render_context = {
    for service_key, service in local.services : service_key => merge(
      local._services_render_base_context[service_key],
      {
        service = local._services_render_services[service_key]

        services = merge(
          local._services_render_services,
          {
            for alias, real_key in local.services_model_imports[service_key] :
            alias => local._services_render_services[real_key]
            if contains(keys(local._services_render_services), real_key)
          },
        )
      },
    )
  }

  # Rendered Docker Compose content keyed by expanded service stack.
  services_render_files_compose = {
    for service_key, compose in local._services_render_files_compose_raw : service_key => yamlencode(merge(
      compose,
      {
        services = {
          for compose_service_key, compose_service in compose.services : compose_service_key => merge(
            compose_service,
            compose_service_key == local._services_render_routing[service_key].container && length(local._services_render_routing[service_key].labels) > 0 ? {
              labels = merge(
                try(compose_service.labels, {}),
                local._services_render_routing[service_key].labels,
              )
            } : {},
          )
        }
      },
    ))
  }

  # Deployed sidecar files include encrypted content metadata used by Fly,
  # Komodo, and TrueNAS GitHub repository file resources.
  services_render_files_sidecars = {
    for file_input in local._services_render_file_inputs : "${file_input.stack}/${file_input.rel_path}" => merge(
      file_input,
      {
        content_base64 = (
          file_input.render_template
          ? base64encode(templatefile(file_input.path, local.services_render_context[file_input.stack]))
          : filebase64(file_input.path)
        )
        content_type = (
          file_input.raw_encrypt
          ? "binary"
          : lookup(local._services_render_file_content_types, try(regex("\\.[^.]+$", lower(file_input.rel_path)), ""), "binary")
        )
      }
    )
  }
}
