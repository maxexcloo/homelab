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

  _services_render_container_inputs = {
    for service_key, service in local.services : service_key => merge(
      service.containers,
      contains(keys(service.containers), local._services_render_primary_container[service_key]) ? {} : {
        (local._services_render_primary_container[service_key]) = {}
      },
      contains(keys(service.containers), local._services_render_routing_container[service_key]) ? {} : {
        (local._services_render_routing_container[service_key]) = {}
      },
    )
  }

  _services_render_container_environment_string = {
    for service_key, containers in local._services_render_container_inputs : service_key => {
      for container_key, container in containers : container_key => {
        for env_key, env_value in try(container.environment, {}) : env_key => (
          can(tostring(env_value))
          ? templatestring(tostring(env_value), local._services_render_pre_context[service_key])
          : join("+", [for env_item in env_value : templatestring(tostring(env_item), local._services_render_pre_context[service_key])])
        )
      }
    }
  }

  _services_render_containers = {
    for service_key, containers in local._services_render_container_inputs : service_key => {
      for container_key, container in containers : container_key => {
        environment = {
          for env_key, env_value in try(container.environment, {}) :
          env_key => local._services_render_container_environment_string[service_key][container_key][env_key]
          if env_value != null && local._services_render_container_environment_string[service_key][container_key][env_key] != ""
        }

        labels = merge(
          container_key == local._services_render_primary_container[service_key] ? local._services_render_dashboard_labels[service_key] : {},
          container_key == local._services_render_routing_container[service_key] ? local._services_render_routing_labels[service_key] : {},
          {
            for label_key, label_value in {
              for k, v in try(container.labels, {}) :
              k => try(templatestring(tostring(v), local._services_render_pre_context[service_key]), null)
              if v != null
            } :
            label_key => label_value
            if label_value != null
          },
        )
        labels_yaml = indent(6, yamlencode(local._services_render_containers_labels[service_key][container_key]))

        envs = [
          for env_key in sort(nonsensitive(keys(local._services_render_containers_environment[service_key][container_key]))) : {
            name  = env_key
            value = local._services_render_containers_environment[service_key][container_key][env_key]
          }
        ]
      }
    }
  }

  _services_render_containers_environment = {
    for service_key, containers in local._services_render_container_inputs : service_key => {
      for container_key, container in containers : container_key => {
        for env_key, env_value in try(container.environment, {}) :
        env_key => local._services_render_container_environment_string[service_key][container_key][env_key]
        if env_value != null && local._services_render_container_environment_string[service_key][container_key][env_key] != ""
      }
    }
  }

  _services_render_containers_labels = {
    for service_key, containers in local._services_render_container_inputs : service_key => {
      for container_key, container in containers : container_key => merge(
        container_key == local._services_render_primary_container[service_key] ? local._services_render_dashboard_labels[service_key] : {},
        container_key == local._services_render_routing_container[service_key] ? local._services_render_routing_labels[service_key] : {},
        {
          for label_key, label_value in {
            for k, v in try(container.labels, {}) :
            k => try(templatestring(tostring(v), local._services_render_pre_context[service_key]), null)
            if v != null
          } :
          label_key => label_value
          if label_value != null
        },
      )
    }
  }

  _services_render_dashboard = {
    for service_key, service in local.services : service_key => merge(
      {
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
        icon   = service.dashboard.icon != null ? templatestring(service.dashboard.icon, local._services_render_pre_context[service_key]) : service.identity.name
        name   = service.dashboard.name != null ? templatestring(service.dashboard.name, local._services_render_pre_context[service_key]) : service.identity.title
        weight = service.dashboard.weight

        widget = {
          for widget_key, widget_value in service.dashboard.widget : widget_key => (
            can(tostring(widget_value))
            ? templatestring(tostring(widget_value), local._services_render_pre_context[service_key])
            : [for widget_item in widget_value : templatestring(tostring(widget_item), local._services_render_pre_context[service_key])]
          )
          if widget_value != null
        }
      },
      service.features.monitoring ? {
        siteMonitor = (
          service.dashboard.href != null ? templatestring(service.dashboard.href, local._services_render_pre_context[service_key])
          : service.fqdn_internal != null ? "https://${service.fqdn_internal}"
          : service.fqdn_external != null ? "https://${service.fqdn_external}"
          : length(service.routing.urls) > 0 ? "${service.routing.ssl ? "https" : "http"}://${service.routing.urls[0]}"
          : null
        )
      } : {},
    )
  }

  # Pre-computed path metadata for every file under templates/services/* so the sidecar
  # loop only adds deployment context (stack key and target).
  _services_render_file_path_info = {
    for file_path in fileset(path.module, "templates/services/*/**") : file_path => {
      raw_encrypt     = endswith(trimsuffix(file_path, ".tftpl"), ".raw")
      rel_path        = trimsuffix(trimsuffix(trimprefix(file_path, "templates/services/${split("/", file_path)[2]}/"), ".tftpl"), ".raw")
      render_template = endswith(file_path, ".tftpl")
    }
  }

  # File extension -> SOPS input type. Files named *.raw or *.raw.tftpl are
  # encrypted as binary and deployed without the .raw suffix for exact decrypts.
  _services_render_files_content_types = {
    ".env"  = "dotenv"
    ".json" = "json"
    ".yaml" = "yaml"
    ".yml"  = "yaml"
  }

  # Only .tftpl files are rendered; the suffix is stripped from the deployed path.
  # Other files use filebase64(), so static and binary assets share one path.
  _services_render_files_inputs = flatten([
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

  _services_render_dashboard_labels = {
    for service_key, service in local.services : service_key => (
      service.dashboard.enabled ? merge(
        {
          "homepage.description" = local._services_render_dashboard[service_key].description
          "homepage.group"       = local._services_render_dashboard[service_key].group
          "homepage.icon"        = local._services_render_dashboard[service_key].icon
          "homepage.name"        = local._services_render_dashboard[service_key].name
          "homepage.weight"      = tostring(local._services_render_dashboard[service_key].weight)
        },
        local._services_render_dashboard[service_key].href != null ? {
          "homepage.href" = local._services_render_dashboard[service_key].href
        } : {},
        try(local._services_render_dashboard[service_key].siteMonitor, null) != null ? {
          "homepage.siteMonitor" = local._services_render_dashboard[service_key].siteMonitor
        } : {},
        {
          for widget_key, widget_value in local._services_render_dashboard[service_key].widget :
          "homepage.widget.${widget_key}" => can(tostring(widget_value)) ? tostring(widget_value) : jsonencode(widget_value)
        },
      ) : {}
    )
  }

  _services_render_primary_container = {
    for service_key, service in local.services : service_key => (
      length(keys(service.containers)) == 1 ? keys(service.containers)[0] : service.identity.service
    )
  }

  _services_render_routing_container = {
    for service_key, service in local.services : service_key => coalesce(
      service.routing.container,
      local._services_render_primary_container[service_key],
    )
  }

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

  # Pre-render context with import aliases overlaid. Used by env and label
  # interpolation; cannot include the rendered env/labels themselves (those
  # would be circular).
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

  # Final template context for compose/sidecar templatefile renders. Adds the
  # rendered containers and reshapes the services map so each entry carries its
  # own dashboard data (used by Homepage dashboard inventory).
  services_render_context = {
    for service_key, service in local.services : service_key => merge(
      local._services_render_pre_context[service_key],
      {
        dashboard  = local._services_render_dashboard[service_key]
        containers = local._services_render_containers[service_key]

        services = merge(
          {
            for k, s in local.services : k => merge(s, {
              dashboard  = local._services_render_dashboard[k]
              containers = local._services_render_containers[k]
            })
          },
          {
            for alias, real_key in local._services_imports[service_key] :
            alias => merge(local.services[real_key], {
              dashboard  = local._services_render_dashboard[real_key]
              containers = local._services_render_containers[real_key]
            })
          },
        )
      },
    )
  }

  # Rendered Docker Compose content keyed by expanded service stack.
  services_render_files_compose = {
    for service_key, service in local.services : service_key => templatefile(
      "${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl",
      local.services_render_context[service_key]
    )
    if fileexists("${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl")
  }

  # Deployed sidecar files include encrypted content metadata used by Fly,
  # Komodo, and TrueNAS GitHub repository file resources.
  services_render_files_sidecars = {
    for file_input in local._services_render_files_inputs : "${file_input.stack}/${file_input.rel_path}" => merge(
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
          : lookup(local._services_render_files_content_types, try(regex("\\.[^.]+$", lower(file_input.rel_path)), ""), "binary")
        )
      }
    )
  }
}
