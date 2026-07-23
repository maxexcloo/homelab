locals {
  # TrueNAS prefers a catalog app when app.json.tftpl exists and falls back to
  # a custom Compose app. Docker targets use docker-compose.yaml.tftpl directly.
  _truenas_render_file_keys = setunion(
    toset([
      for service_key, service in local.truenas_services : "${service.target}/${service.identity.name}/compose.json"
      if(
        !can(local.truenas_catalog_templates[service_key]) &&
        fileexists("${path.root}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl")
      )
    ]),
    toset([
      for service_key, service in local.truenas_services : "${service.target}/${service.identity.name}/app.json"
      if can(local.truenas_catalog_templates[service_key])
    ]),
    toset([
      for file_input in values(local.services_render_sidecar_inputs) : "${file_input.target}/${local.services_model[file_input.stack].identity.name}/${file_input.rel_path}"
      if can(local.truenas_servers[file_input.target])
    ]),
  )

  _truenas_render_files = merge(
    {
      for service_key, service in local.truenas_services : "${service.target}/${service.identity.name}/compose.json" => {
        age_public_key = var.servers.age_public_keys[service.target]
        commit_message = "Update ${service_key} compose"
        content_type   = "json"
        file           = "${service.target}/${service.identity.name}/compose.json"

        content_base64 = sensitive(
          base64encode(
            templatefile(
              "${path.root}/templates/truenas/compose.json.tftpl",
              merge(
                local.services_render_template_context[service_key],
                {
                  compose = local.services_render_compose[service_key]
                },
              ),
            ),
          ),
        )
      }
      if(
        !can(local.truenas_catalog_templates[service_key]) &&
        fileexists("${path.root}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl")
      )
    },
    {
      for service_key, service in local.truenas_services : "${service.target}/${service.identity.name}/app.json" => {
        age_public_key = var.servers.age_public_keys[service.target]
        commit_message = "Update ${service_key} catalog app"
        content_type   = "json"
        file           = "${service.target}/${service.identity.name}/app.json"

        content_base64 = sensitive(
          base64encode(
            jsonencode(
              provider::deepmerge::mergo(
                jsondecode(
                  templatefile(
                    "${path.root}/templates/truenas/app.json.tftpl",
                    local.services_render_template_context[service_key],
                  ),
                ),
                jsondecode(
                  templatefile(
                    local.truenas_catalog_templates[service_key],
                    local.services_render_template_context[service_key],
                  ),
                ),
              ),
            ),
          ),
        )
      }
      if can(local.truenas_catalog_templates[service_key])
    },
    {
      for sidecar_key, file_input in local.services_render_sidecar_inputs : "${file_input.target}/${local.services_model[file_input.stack].identity.name}/${file_input.rel_path}" => merge(
        local.services_render_sidecars[sidecar_key],
        {
          age_public_key = var.servers.age_public_keys[file_input.target]
          commit_message = "Update ${file_input.stack} ${file_input.rel_path}"
          file           = "${file_input.target}/${local.services_model[file_input.stack].identity.name}/${file_input.rel_path}"
        },
      )
      if can(local.truenas_servers[file_input.target])
    }
  )

  truenas_catalog_templates = {
    for service_key, service in local.truenas_services :
    service_key => "${path.root}/templates/services/${service.identity.service}/app.json.tftpl"
    if fileexists("${path.root}/templates/services/${service.identity.service}/app.json.tftpl")
  }

  truenas_servers = {
    for server_key, server in local.servers_model : server_key => server
    if server.platform == "truenas"
  }

  truenas_services = {
    for service_key, service in local.services_model : service_key => service
    if(
      service.identity.service != null &&
      can(local.truenas_servers[service.target])
    )
  }
}
