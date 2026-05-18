locals {
  # Deploy artifacts are grouped by target server: each server has its own
  # self-hosted runner and age key.
  truenas_input_servers = {
    for server_key, server in local.servers_model : server_key => server
    if server.platform == "truenas"
  }

  truenas_input_services = {
    for service_key, service in local.services_model : service_key => service
    if lookup(local.truenas_input_servers, service.target, null) != null &&
    service.identity.service != null
  }

  truenas_prepare_catalog_templates = {
    for service_key, service in local.truenas_input_services : service_key => {
      path = "${path.module}/templates/services/${service.identity.service}/app.json.tftpl"
    }
    if service.identity.service != null && fileexists("${path.module}/templates/services/${service.identity.service}/app.json.tftpl")
  }

  # Compose wins over catalog: a service with docker-compose.yaml.tftpl deploys
  # as a custom stack; otherwise app.json.tftpl is used. Sidecars are always included.
  truenas_render_files = merge(
    {
      # 1) Custom Docker Compose apps
      for service_key, service in local.truenas_input_services : "${service.target}/${service.identity.name}/compose.json" => {
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
                  compose = local.services_render_files_compose[service_key]
                },
              ),
            ),
          ),
        )
      }
      if fileexists("${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl")
    },
    {
      # 2) TrueNAS catalog apps — only when no custom compose file exists
      for service_key, service in local.truenas_input_services : "${service.target}/${service.identity.name}/app.json" => {
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
                    local.truenas_prepare_catalog_templates[service_key].path,
                    local.services_render_template_context[service_key],
                  ),
                ),
              ),
            ),
          ),
        )
      }
      if !fileexists("${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl") &&
      lookup(local.truenas_prepare_catalog_templates, service_key, null) != null
    },
    {
      # 3) Generic sidecar files (env, configs, etc.)
      for file_key, file_config in local.services_render_files_sidecars : "${file_config.target}/${local.services_model[file_config.stack].identity.name}/${file_config.rel_path}" => merge(
        file_config,
        {
          age_public_key = age_secret_key.server[file_config.target].public_key
          commit_message = "Update ${file_config.stack} ${file_config.rel_path}"
          file           = "${file_config.target}/${local.services_model[file_config.stack].identity.name}/${file_config.rel_path}"
        },
      )
      if lookup(local.truenas_input_servers, file_config.target, null) != null
    }
  )
}

# GitHub secret names cannot contain hyphens, so the workflow matrix computes
# the same uppercase-underscore form from the server key.
resource "github_actions_secret" "truenas_age_key" {
  for_each = local.truenas_input_servers

  repository  = local.defaults.github.repositories.truenas
  secret_name = "AGE_KEY_${upper(replace(each.key, "-", "_"))}"
  value       = age_secret_key.server[each.key].secret_key
}

resource "github_repository_file" "truenas_deploy_request" {
  commit_message      = "Request changed deployments"
  file                = ".github/deploy-request.json"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas

  content = jsonencode({
    deployments = {
      for service_key, service in local.truenas_input_services : "${service.target}/${service.identity.name}" => sha256(jsonencode({
        workflow_files = local.github_workflow_file_hashes.truenas

        files = {
          for file_key, file_config in local.truenas_render_files : file_config.file => nonsensitive(sha256(file_config.content_base64))
          if startswith(local.truenas_render_files[file_key].file, "${service.target}/${service.identity.name}/")
        }

        sops = sha256(yamlencode({
          creation_rules = [
            for server_key, server in local.truenas_input_servers : {
              age        = age_secret_key.server[server_key].public_key
              path_regex = "^${server_key}/"
            }
          ]
        }))
      }))
    }
  })

  depends_on = [
    github_repository_file.truenas_sops_config,
    github_repository_file.workflow_file,
    module.encrypted_github_file_truenas,
  ]
}

module "encrypted_github_file_truenas" {
  for_each = nonsensitive(local.truenas_render_files)
  source   = "./modules/github_file_encrypted"

  age_public_key = each.value.age_public_key
  commit_message = each.value.commit_message
  content_base64 = each.value.content_base64
  content_type   = each.value.content_type
  debug_path     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.truenas}/${each.key}" : ""
  file           = each.value.file
  repository     = local.defaults.github.repositories.truenas
}

resource "github_repository_file" "truenas_sops_config" {
  commit_message      = "Update SOPS configuration"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas

  content = yamlencode({
    creation_rules = [
      for server_key, server in local.truenas_input_servers : {
        age        = age_secret_key.server[server_key].public_key
        path_regex = "^${server_key}/"
      }
    ]
  })
}
