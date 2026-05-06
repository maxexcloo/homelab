locals {
  # Per-service: import alias → resolved real service key. Built once and
  # reused for both label/env rendering and the final template context.
  _services_imports = {
    for service_key, service in local.services : service_key => {
      for import_alias, service_ref in service.imports.services :
      import_alias => templatestring(service_ref, {
        service = service
      })
      if contains(keys(local.services), templatestring(service_ref, {
        service = service
      }))
    }
  }

  # Final per-container runtime data exposed to templates. Generated Traefik
  # labels attach only to routing.container; Homepage uses dashboard instead.
  _services_render_containers = {
    for service_key, service in local.services : service_key => {
      for container_key in sort(distinct(concat(keys(service.containers), [local._services_render_routing_container[service_key]]))) : container_key => {
        environment = {
          for env_key, env_value in {
            for raw_key, raw_value in try(service.containers[container_key].environment, {}) : raw_key => (
              can(tostring(raw_value))
              ? templatestring(tostring(raw_value), local._services_render_pre_context[service_key])
              : join("+", [for env_item in raw_value : templatestring(tostring(env_item), local._services_render_pre_context[service_key])])
            )
            if raw_value != null
          } :
          env_key => env_value
          if env_value != ""
        }
        labels = merge(
          container_key == local._services_render_routing_container[service_key] ? local._services_render_routing_labels[service_key] : {},
          {
            for label_key, label_value in {
              for k, v in try(service.containers[container_key].labels, {}) :
              k => try(templatestring(tostring(v), local._services_render_pre_context[service_key]), null)
              if v != null
            } :
            label_key => label_value
            if label_value != null
          },
        )
      }
    }
  }

  # Structured Homepage data consumed by the Homepage config template.
  _services_render_dashboard = {
    for service_key, service in local.services : service_key => {
      description = service.dashboard.description != null ? templatestring(service.dashboard.description, local._services_render_pre_context[service_key]) : service.identity.description
      enabled     = service.dashboard.enabled
      group       = service.dashboard.group != null ? templatestring(service.dashboard.group, local._services_render_pre_context[service_key]) : service.identity.group
      href = (
        service.dashboard.href != null ? templatestring(service.dashboard.href, local._services_render_pre_context[service_key])
        : service.fqdn_internal != null ? "https://${service.fqdn_internal}"
        : service.fqdn_external != null ? "https://${service.fqdn_external}"
        : length(service.routing.urls) > 0 ? "${service.routing.ssl ? "https" : "http"}://${service.routing.urls[0]}"
        : null
      )
      icon = service.dashboard.icon != null ? templatestring(service.dashboard.icon, local._services_render_pre_context[service_key]) : service.identity.name
      name = service.dashboard.name != null ? templatestring(service.dashboard.name, local._services_render_pre_context[service_key]) : service.identity.title
      siteMonitor = service.features.monitoring ? (
        service.dashboard.href != null ? templatestring(service.dashboard.href, local._services_render_pre_context[service_key])
        : service.fqdn_internal != null ? "https://${service.fqdn_internal}"
        : service.fqdn_external != null ? "https://${service.fqdn_external}"
        : length(service.routing.urls) > 0 ? "${service.routing.ssl ? "https" : "http"}://${service.routing.urls[0]}"
        : null
      ) : null
      weight = service.dashboard.weight

      widget = {
        for widget_key, widget_value in service.dashboard.widget : widget_key => (
          can(tostring(widget_value))
          ? templatestring(tostring(widget_value), local._services_render_pre_context[service_key])
          : [for widget_item in widget_value : templatestring(tostring(widget_item), local._services_render_pre_context[service_key])]
        )
        if widget_value != null
      }
    }
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
  # rendered containers/dashboard data because env, label, and dashboard strings
  # are rendered from this context.
  _services_render_pre_context = {
    for service_key, service in local.services : service_key => {
      defaults = local.defaults
      server   = try(local.servers[service.target], null)
      servers  = local.servers
      service  = service
      services = merge(
        local.services,
        {
          for alias, real_key in local._services_imports[service_key] :
          alias => local.services[real_key]
        },
      )
    }
  }

  _services_render_routing_container = {
    for service_key, service in local.services : service_key => coalesce(
      service.routing.container,
      length(keys(service.containers)) == 1 ? keys(service.containers)[0] : service.identity.service,
    )
  }

  # Generated Traefik labels plus routing.labels overrides. The result is
  # attached only to routing.container.
  _services_render_routing_labels = {
    for service_key, service in local.services : service_key => merge(
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
        service.routing.expose == "tailscale" ? {
          "traefik.http.routers.${service.identity.name}.middlewares" = "tailscale-only@docker"
        } : {},
        service.routing.scheme == "https" ? {
          "traefik.http.services.${service.identity.name}.loadbalancer.server.scheme" = "https"
        } : {},
      ) : {},

      {
        for label_key, label_value in {
          for k, v in service.routing.labels :
          k => try(templatestring(tostring(v), local._services_render_pre_context[service_key]), null)
          if v != null
        } :
        label_key => label_value
        if label_value != null
      },
    )
  }

  # Final template context for compose/sidecar renders. Imported service aliases
  # are overlaid here so templates can reference `services.<alias>`.
  services_render_context = {
    for service_key, service in local.services : service_key => merge(
      local._services_render_pre_context[service_key],
      {
        containers = local._services_render_containers[service_key]
        dashboard  = local._services_render_dashboard[service_key]

        services = merge(
          {
            for k, s in local.services : k => merge(s, {
              containers = local._services_render_containers[k]
              dashboard  = local._services_render_dashboard[k]
            })
          },
          {
            for alias, real_key in local._services_imports[service_key] :
            alias => merge(local.services[real_key], {
              containers = local._services_render_containers[real_key]
              dashboard  = local._services_render_dashboard[real_key]
            })
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
            contains(keys(local._services_render_containers[service_key]), compose_service_key) && length(local._services_render_containers[service_key][compose_service_key].environment) > 0 ? {
              environment = merge(
                try(compose_service.environment, {}),
                local._services_render_containers[service_key][compose_service_key].environment,
              )
            } : {},
            contains(keys(local._services_render_containers[service_key]), compose_service_key) && length(local._services_render_containers[service_key][compose_service_key].labels) > 0 ? {
              labels = merge(
                try(compose_service.labels, {}),
                local._services_render_containers[service_key][compose_service_key].labels,
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
