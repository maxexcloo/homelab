locals {
  # TrueNAS prefers a catalog app when app.json.tftpl exists and falls back to
  # a custom Compose app. Docker targets use docker-compose.yaml.tftpl directly.
  _truenas_render_file_keys = setunion(
    toset([
      for service_key, service in local.truenas_services : "${service.target}/${service.identity.name}/compose.json"
      if(
        !can(local.truenas_catalog_templates[service_key]) &&
        fileexists("${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl")
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
        age_public_key = age_secret_key.server[service.target].public_key
        commit_message = "Update ${service_key} compose"
        content_type   = "json"
        file           = "${service.target}/${service.identity.name}/compose.json"

        content_base64 = sensitive(
          base64encode(
            templatefile(
              "${path.module}/templates/truenas/compose.json.tftpl",
              merge(
                local.services_render_template_context[service_key],
                {
                  compose = local.services_render_write_compose[service_key]
                },
              ),
            ),
          ),
        )
      }
      if(
        !can(local.truenas_catalog_templates[service_key]) &&
        fileexists("${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl")
      )
    },
    {
      for service_key, service in local.truenas_services : "${service.target}/${service.identity.name}/app.json" => {
        age_public_key = age_secret_key.server[service.target].public_key
        commit_message = "Update ${service_key} catalog app"
        content_type   = "json"
        file           = "${service.target}/${service.identity.name}/app.json"

        content_base64 = sensitive(
          base64encode(
            jsonencode(
              provider::deepmerge::mergo(
                jsondecode(
                  templatefile(
                    "${path.module}/templates/truenas/app.json.tftpl",
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
        local.services_render_write_sidecars[sidecar_key],
        {
          age_public_key = age_secret_key.server[file_input.target].public_key
          commit_message = "Update ${file_input.stack} ${file_input.rel_path}"
          file           = "${file_input.target}/${local.services_model[file_input.stack].identity.name}/${file_input.rel_path}"
        },
      )
      if can(local.truenas_servers[file_input.target])
    }
  )

  truenas_catalog_templates = {
    for service_key, service in local.truenas_services :
    service_key => "${path.module}/templates/services/${service.identity.service}/app.json.tftpl"
    if fileexists("${path.module}/templates/services/${service.identity.service}/app.json.tftpl")
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

resource "github_repository_file" "truenas_sops_config" {
  commit_message      = "Update SOPS configuration"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = github_repository.deployment["truenas"].name

  content = yamlencode({
    creation_rules = [
      for server_key in keys(local.truenas_servers) : {
        age        = age_secret_key.server[server_key].public_key
        path_regex = "^${server_key}/"
      }
    ]
  })
}

module "encrypted_github_file_truenas" {
  for_each = local._truenas_render_file_keys
  source   = "./modules/github_file_encrypted"

  age_public_key = local._truenas_render_files[each.key].age_public_key
  commit_message = local._truenas_render_files[each.key].commit_message
  content_base64 = local._truenas_render_files[each.key].content_base64
  content_type   = local._truenas_render_files[each.key].content_type
  debug_path     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.deployment_repositories.truenas.name}/${each.key}" : ""
  file           = local._truenas_render_files[each.key].file
  repository     = github_repository.deployment["truenas"].name
}

resource "github_repository_file" "truenas_deploy_request" {
  commit_message      = "Request changed deployments"
  file                = ".github/deploy-request.json"
  overwrite_on_create = true
  repository          = github_repository.deployment["truenas"].name

  content = jsonencode({
    workflow_revision = local.github_workflow_revisions.truenas

    deployments = {
      for service in values(local.truenas_services) : "${service.target}/${service.identity.name}" => {
        files = sort([
          for file_key in local._truenas_render_file_keys : file_key
          if startswith(file_key, "${service.target}/${service.identity.name}/")
        ])

        hash = sha256(jsonencode({
          files = {
            for file_config in values(local._truenas_render_files) : file_config.file => nonsensitive(sha256(file_config.content_base64))
            if startswith(file_config.file, "${service.target}/${service.identity.name}/")
          }

          sops = sha256(age_secret_key.server[service.target].public_key)
        }))
      }
    }
  })

  depends_on = [
    github_repository_file.truenas_sops_config,
    github_repository_file.workflow_file,
    module.encrypted_github_file_truenas,
  ]
}
