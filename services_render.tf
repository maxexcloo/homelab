locals {
  # Pre-render every env value to a string so the filter below doesn't repeat
  # the rendering expression.
  _services_env_string = {
    for service_key, service in local.services_outputs_private : service_key => {
      for env_key, env_value in service.platform_config.docker.env : env_key => try(
        join("+", [for env_item in env_value : templatestring(tostring(env_item), local.services_template_context_base[service_key])]),
        templatestring(tostring(env_value), local.services_template_context_base[service_key])
      )
    }
  }

  # Pre-computed path metadata for every file under services/* so the per-stack
  # loop below only adds deployment context (stack key and target).
  _services_file_path_info = {
    for file_path in fileset(path.module, "services/*/**") : file_path => {
      raw_encrypt     = endswith(trimsuffix(file_path, ".tftpl"), ".raw")
      rel_path        = trimsuffix(trimsuffix(trimprefix(file_path, "services/${split("/", file_path)[1]}/"), ".tftpl"), ".raw")
      render_template = endswith(file_path, ".tftpl")
    }
  }

  # Docker env is stored as typed YAML but rendered as strings for deployment.
  services_render_context_env = {
    for service_key, service in local.services_outputs_private : service_key => {
      for env_key, env_value in service.platform_config.docker.env : env_key => local._services_env_string[service_key][env_key]
      if env_value != null && local._services_env_string[service_key][env_key] != ""
    }
  }

  # Final template context merges the base context with rendered env, labels, and
  # the public service inventory so templates can reference the complete picture.
  services_render_context_final = {
    for service_key, service in local.services_outputs_private : service_key => merge(
      local.services_template_context_base[service_key],
      {
        env         = local.services_render_context_env[service_key]
        labels      = local.services_render_context_labels[service_key]
        labels_yaml = indent(6, yamlencode(local.services_render_context_labels[service_key]))

        envs = [
          for env_key in sort(nonsensitive(keys(local.services_render_context_env[service_key]))) : {
            name  = env_key
            value = local.services_render_context_env[service_key][env_key]
          }
        ]

        services = {
          for public_service_key, public_service in local.services_outputs_public : public_service_key => merge(
            public_service,
            {
              labels = local.services_render_context_labels[public_service_key]
            }
          )
        }
    })
  }

  # Routing label rules live in a template; service-owned labels are plain data.
  services_render_context_labels = {
    for service_key, service in local.services_outputs_private : service_key => merge(
      yamldecode(templatefile("${path.module}/templates/docker/labels.yaml.tftpl", local.services_template_context_base[service_key])),
      {
        for label_key, label_value in service.platform_config.docker.labels :
        label_key => templatestring(tostring(label_value), local.services_template_context_base[service_key])
        if label_value != null
      }
    )
  }

  # Rendered Docker Compose content keyed by expanded service stack.
  services_render_files_compose = {
    for service_key, service in local.services_model_desired : service_key => templatefile(
      "${path.module}/services/${service.identity.service}/docker-compose.yaml.tftpl",
      local.services_render_context_final[service_key]
    )
    if fileexists("${path.module}/services/${service.identity.service}/docker-compose.yaml.tftpl")
  }

  # File extension -> SOPS input type. Files named *.raw or *.raw.tftpl are
  # encrypted as binary and deployed without the .raw suffix for exact decrypts.
  services_render_files_content_types = {
    ".env"  = "dotenv"
    ".json" = "json"
    ".yaml" = "yaml"
    ".yml"  = "yaml"
  }

  # Only .tftpl files are rendered; the suffix is stripped from the deployed path.
  # Other files use filebase64(), so static and binary assets share one path.
  services_render_files_inputs = flatten([
    for service_key, service in local.services_model_desired : [
      for file_path in fileset(path.module, "services/${service.identity.service}/**") : merge(
        local._services_file_path_info[file_path],
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

  # Deployed sidecar files include encrypted content metadata used by Fly, Komodo,
  # and TrueNAS GitHub repository file resources.
  services_render_files_sidecars = {
    for file_input in local.services_render_files_inputs : "${file_input.stack}/${file_input.rel_path}" => merge(
      file_input,
      {
        content_base64 = (
          file_input.render_template
          ? base64encode(templatefile(file_input.path, local.services_render_context_final[file_input.stack]))
          : filebase64(file_input.path)
        )
        content_type = (
          file_input.raw_encrypt
          ? "binary"
          : lookup(local.services_render_files_content_types, try(regex("\\.[^.]+$", lower(file_input.rel_path)), ""), "binary")
        )
      }
    )
  }

  # First-pass template context used to resolve import aliases. Only public
  # service data is available here to avoid circular dependencies on runtime
  # fields (the runtime model depends on feature resources, which in turn depend
  # on the feature maps built from input).
  services_template_context_public = {
    for service_key, service in local.services_model_desired : service_key => {
      defaults = local.defaults
      server   = try(local.servers_outputs_public[service.target], null)
      servers  = local.servers_outputs_public
      service  = service
      services = local.services_outputs_public
    }
  }
}
