# Stage: render — sidecar file inventory and rendered sidecar content.
locals {
  # Sidecar file inventory discovered from templates/services/**/. Platform-specific
  # entry points (app.json.tftpl, docker-compose.yaml.tftpl) are handled by their
  # respective platform deployers and excluded here.
  _services_render_sidecar_inputs = flatten([
    for service_key, service in {
      for service_key, service in local.services_model : service_key => service
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
      if !contains(["app.json.tftpl", "docker-compose.yaml.tftpl"], basename(file_path))
    ]
  ])

  # Sidecar files (env files, configs, etc.) with rendered content and SOPS content type.
  services_render_write_sidecars = {
    for file_input in local._services_render_sidecar_inputs : "${file_input.stack}/${file_input.rel_path}" => merge(
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
}
