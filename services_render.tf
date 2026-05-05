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

  # Docker env stored as typed YAML, rendered as strings for deployment.
  _services_render_env = {
    for service_key, service in local.services : service_key => {
      for env_key, env_value in service.container.env : env_key => local._services_render_env_string[service_key][env_key]
      if env_value != null && local._services_render_env_string[service_key][env_key] != ""
    }
  }

  # Pre-render every env value to a string so the filter above doesn't repeat
  # the rendering expression. List values join with `+`; scalars render as-is.
  # `tostring()` succeeds for strings/numbers/bools and fails for lists, which
  # is the cleanest way to switch on the YAML schema's value types.
  _services_render_env_string = {
    for service_key, service in local.services : service_key => {
      for env_key, env_value in service.container.env : env_key => (
        can(tostring(env_value))
        ? templatestring(tostring(env_value), local._services_render_pre_context[service_key])
        : join("+", [for env_item in env_value : templatestring(tostring(env_item), local._services_render_pre_context[service_key])])
      )
    }
  }

  # Pre-computed path metadata for every file under services/* so the sidecar
  # loop only adds deployment context (stack key and target).
  _services_render_file_path_info = {
    for file_path in fileset(path.module, "services/*/**") : file_path => {
      raw_encrypt     = endswith(trimsuffix(file_path, ".tftpl"), ".raw")
      rel_path        = trimsuffix(trimsuffix(trimprefix(file_path, "services/${split("/", file_path)[1]}/"), ".tftpl"), ".raw")
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
      for file_path in fileset(path.module, "services/${service.identity.service}/**") : merge(
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

  # Generated labels per service. Three groups merged in order so user labels
  # win:
  #   1. Homepage dashboard labels (auto-suppressed when homelab.homepage.enabled=false)
  #   2. Traefik routing labels (only when networking.port is set)
  #   3. User-defined labels from service.container.labels, with template
  #      interpolation against the pre-context (labels can reference imports).
  _services_render_labels = {
    for service_key, service in local.services : service_key => merge(
      (service.networking.port != null || length(service.container.labels) > 0) &&
      lookup(service.container.labels, "homelab.homepage.enabled", true) ? {
        "homepage.description" = service.identity.description
        "homepage.group"       = service.identity.group
        "homepage.icon"        = service.identity.name
        "homepage.name"        = service.identity.title
        "homepage.weight"      = contains(keys(service.container.labels), "homepage.widget.type") ? "-10" : "0"

        "homepage.href" = (
          service.fqdn_internal != null ? "https://${service.fqdn_internal}"
          : service.fqdn_external != null ? "https://${service.fqdn_external}"
          : length(service.networking.urls) > 0 ? service.networking.urls[0]
          : null
        )
      } : {},

      service.networking.port != null ? merge(
        {
          "traefik.enable"                                                          = "true"
          "traefik.http.routers.${service.identity.name}.entrypoints"               = service.networking.ssl ? "websecure" : "web"
          "traefik.http.services.${service.identity.name}.loadbalancer.server.port" = tostring(service.networking.port)

          "traefik.http.routers.${service.identity.name}.rule" = join(" || ", concat(
            service.fqdn_internal != null ? ["Host(`${service.fqdn_internal}`)"] : [],
            service.fqdn_external != null ? ["Host(`${service.fqdn_external}`)"] : [],
            [for url in service.networking.urls : "Host(`${url}`)"],
          ))
        },
        service.networking.expose == "internal" ? {
          "traefik.http.routers.${service.identity.name}.middlewares" = "internal-only@docker"
        } : {},
        service.networking.expose == "tailscale" ? {
          "traefik.http.routers.${service.identity.name}.middlewares" = "tailscale-only@docker"
        } : {},
        service.networking.scheme == "https" ? {
          "traefik.http.services.${service.identity.name}.loadbalancer.server.scheme" = "https"
        } : {},
      ) : {},

      {
        for label_key, label_value in service.container.labels :
        label_key => templatestring(tostring(label_value), local._services_render_pre_context[service_key])
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
  # rendered env/labels/envs and reshapes the services map so each entry
  # carries its own labels (used by Homepage dashboard inventory).
  services_render_context = {
    for service_key, service in local.services : service_key => merge(
      local._services_render_pre_context[service_key],
      {
        env         = local._services_render_env[service_key]
        labels      = local._services_render_labels[service_key]
        labels_yaml = indent(6, yamlencode(local._services_render_labels[service_key]))

        envs = [
          for env_key in sort(nonsensitive(keys(local._services_render_env[service_key]))) : {
            name  = env_key
            value = local._services_render_env[service_key][env_key]
          }
        ]

        services = merge(
          {
            for k, s in local.services : k => merge(s, {
              labels = local._services_render_labels[k]
            })
          },
          {
            for alias, real_key in local._services_imports[service_key] :
            alias => merge(local.services[real_key], {
              labels = local._services_render_labels[real_key]
            })
          },
        )
      },
    )
  }

  # Rendered Docker Compose content keyed by expanded service stack.
  services_render_files_compose = {
    for service_key, service in local.services : service_key => templatefile(
      "${path.module}/services/${service.identity.service}/docker-compose.yaml.tftpl",
      local.services_render_context[service_key]
    )
    if fileexists("${path.module}/services/${service.identity.service}/docker-compose.yaml.tftpl")
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
