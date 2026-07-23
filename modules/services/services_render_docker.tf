locals {
  _docker_render_file_keys = setunion(
    toset([
      for server_key in keys(local._docker_servers) : ".doco-cd.${server_key}.yml"
    ]),
    toset([
      for service in values(local._docker_services) : "${service.target}/${service.identity.name}/compose.yaml"
    ]),
    toset([
      for file_input in values(local.services_render_sidecar_inputs) : "${file_input.target}/${local.services_model[file_input.stack].identity.name}/${file_input.rel_path}"
      if can(local._docker_services[file_input.stack])
    ]),
  )

  _docker_render_files = merge(
    {
      for server_key, server in local._docker_servers : ".doco-cd.${server_key}.yml" => {
        age_public_key = var.servers.age_public_keys[server_key]
        commit_message = "Update ${server_key} doco-cd config"
        content_type   = "yaml"
        encrypt        = false
        file           = ".doco-cd.${server_key}.yml"

        content_base64 = sensitive(base64encode(yamlencode({
          working_dir = server_key

          auto_discovery = {
            delete         = true
            depth          = 1
            enabled        = true
            remove_images  = true
            remove_volumes = false
          }
        })))
      }
    },
    {
      for service_key, service in local._docker_services : "${service.target}/${service.identity.name}/compose.yaml" => {
        age_public_key = var.servers.age_public_keys[service.target]
        commit_message = "Update ${service_key} compose"
        content_base64 = sensitive(base64encode(local.services_render_compose[service_key]))
        content_type   = "yaml"
        encrypt        = true
        file           = "${service.target}/${service.identity.name}/compose.yaml"
      }
    },
    {
      for sidecar_key, file_input in local.services_render_sidecar_inputs : "${file_input.target}/${local.services_model[file_input.stack].identity.name}/${file_input.rel_path}" => merge(
        local.services_render_sidecars[sidecar_key],
        {
          age_public_key = var.servers.age_public_keys[file_input.target]
          commit_message = "Update ${file_input.stack} ${file_input.rel_path}"
          encrypt        = true
          file           = "${file_input.target}/${local.services_model[file_input.stack].identity.name}/${file_input.rel_path}"
        },
      )
      if can(local._docker_services[file_input.stack])
    }
  )

  _docker_servers = {
    for server_key, server in local.servers_model : server_key => server
    if server.features.docker
  }

  _docker_services = {
    for service_key, service in local.services_model : service_key => service
    if(
      can(local._docker_servers[service.target]) &&
      can(local.services_render_compose_inputs[service_key])
    )
  }

}
