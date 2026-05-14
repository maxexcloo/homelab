locals {
  # Generic sidecars share one path model; templates render, static files copy.
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

  _services_render_files_compose_raw = {
    for service_key, service in local.services : service_key => yamldecode(
      templatefile(
        "${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl",
        local.services_render_template_context[service_key],
      ),
    )
    if service.identity.service != null &&
    fileexists("${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl") &&
    (
      contains(keys(local.truenas_input_servers), service.target) ||
      (
        contains(keys(local.servers_model), service.target) &&
        local.servers_model[service.target].features.docker
      )
    )
  }

  _services_render_public_raw_services = {
    for service_key, service in local.services : service_key => {
      for k, v in service : k => v if k != "runtime"
    }
  }

  _services_render_public_rendered_services = {
    for service_key, service in local.services_render_services : service_key => {
      for k, v in service : k => v if k != "runtime"
    }
  }

  _services_render_routing_labels = {
    for service_key, service in local.services : service_key => {
      for label_key, label_value in merge(
        service.routing.port != null ? {
          # Explicit resolver avoids first-hit TLS failures.
          "traefik.enable"                                                            = "true"
          "traefik.http.routers.${service.identity.name}.entrypoints"                 = service.routing.ssl ? "websecure" : "web"
          "traefik.http.routers.${service.identity.name}.middlewares"                 = service.routing.expose == "internal" ? "internal-only@docker" : null
          "traefik.http.routers.${service.identity.name}.tls.certresolver"            = service.routing.ssl && service.routing.expose != "cloudflare" ? "cloudflare" : null
          "traefik.http.services.${service.identity.name}.loadbalancer.server.port"   = tostring(coalesce(service.routing.backend_port, service.routing.port))
          "traefik.http.services.${service.identity.name}.loadbalancer.server.scheme" = service.routing.scheme == "https" ? "https" : null

          "traefik.http.routers.${service.identity.name}.rule" = join(" || ", [
            for host in distinct([
              for url_key, url in service.urls : url.host
              if url_key != "default" && url.host != null && url.host != ""
            ]) : "Host(`${host}`)"
          ])
        } : {},
        # Only managed DNS zones can resolve ACME DNS-01 challenges.
        service.routing.port != null && service.routing.ssl && service.routing.expose != "cloudflare" ? {
          for url_index, url in [
            for url in service.routing.urls : url
            if lookup(local.dns_render_managed_zones_by_url, url, null) != null
          ] :
          "traefik.http.routers.${service.identity.name}.tls.domains[${url_index}].main" => url
        } : {},
        {
          for label_key, label_value in service.routing.labels :
          label_key => try(templatestring(tostring(label_value), local.services_render_pre_template_context[service_key]), null)
          if label_value != null
        }
      ) : label_key => label_value
      if label_value != null
    }
  }

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

  # Pre-render context avoids circular references while templating data strings.
  services_render_pre_template_context = {
    for service_key, service in local.services : service_key => {
      defaults = local.defaults
      server   = try(local.servers_runtime_rendered[service.target], null)
      servers  = local.servers_runtime_rendered
      service  = service

      services = merge(
        local._services_render_public_raw_services,
        {
          for alias, real_key in local.services_model_imports[service_key] :
          alias => local.services[real_key]
          if contains(keys(local.services), real_key)
        },
      )
    }
  }

  # Rendered service inventory for templates and platform deployers.
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
          local.services_render_pre_template_context[service_key],
        ),
      ),
      {
        routing_labels = local._services_render_routing_labels[service_key]
      },
    )
  }

  services_render_template_context = {
    for service_key, service in local.services : service_key => merge(
      local.services_render_pre_template_context[service_key],
      {
        custom  = lookup(local.services_render_custom_context, service_key, {})
        service = local.services_render_services[service_key]

        services = merge(
          local._services_render_public_rendered_services,
          {
            for alias, real_key in local.services_model_imports[service_key] :
            alias => local.services_render_services[real_key]
            if contains(keys(local.services_render_services), real_key)
          },
        )
      },
    )
  }
}
