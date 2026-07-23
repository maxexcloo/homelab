locals {
  _fly_render_file_keys = setunion(
    toset([
      for service in values(local._fly_services) : "${service.fly.app_name}/fly.toml"
    ]),
    toset([
      for service in values(local._fly_services) : "${service.fly.app_name}/.certs"
      if length([for route in service.routing.routes : route if route.host_configured]) > 0
    ]),
    toset([
      for service in values(local._fly_services) : "${service.fly.app_name}/.machine-count"
      if service.fly.machine_count != null
    ]),
    toset([
      for file_input in values(local.services_render_sidecar_inputs) : "${local._fly_services[file_input.stack].fly.app_name}/${file_input.rel_path}"
      if file_input.target == "fly"
    ]),
  )

  # Rendered content for the deterministic file inventory.
  _fly_render_files = merge(
    {
      for service_key, service in local._fly_services : "${service.fly.app_name}/fly.toml" => {
        commit_message = "Update ${service.fly.app_name} configuration"
        file           = "${service.fly.app_name}/fly.toml"

        content_base64 = sensitive(
          base64encode(
            templatefile(
              "${path.root}/templates/fly/fly.toml.tftpl",
              local.services_render_template_context[service_key],
            ),
          ),
        )
      }
    },
    {
      for service_key, service in local._fly_services : "${service.fly.app_name}/.certs" => {
        commit_message = "Update ${service.fly.app_name} certificate hostnames"
        file           = "${service.fly.app_name}/.certs"

        content_base64 = base64encode(
          templatefile(
            "${path.root}/templates/fly/certs.tftpl",
            local.services_render_template_context[service_key],
          ),
        )
      }
      if length([
        for route in service.routing.routes : route
        if route.host_configured
      ]) > 0
    },
    {
      for service in values(local._fly_services) : "${service.fly.app_name}/.machine-count" => {
        commit_message = "Update ${service.fly.app_name} machine count"
        content_base64 = base64encode("${service.fly.machine_count}\n")
        file           = "${service.fly.app_name}/.machine-count"
      }
      if service.fly.machine_count != null
    },
    {
      for sidecar_key, file_input in local.services_render_sidecar_inputs : "${local._fly_services[file_input.stack].fly.app_name}/${file_input.rel_path}" => merge(
        local.services_render_sidecars[sidecar_key],
        {
          commit_message = "Update ${file_input.stack} ${file_input.rel_path}"
          file           = "${local._fly_services[file_input.stack].fly.app_name}/${file_input.rel_path}"
        },
      )
      if file_input.target == "fly"
    }
  )

  _fly_services = {
    for service_key, service in local.services_model : service_key => service
    if(
      service.target == "fly" &&
      service.identity.service != null
    )
  }
}
