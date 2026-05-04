locals {
  # TrueNAS deploy artifacts are grouped by target server because each server has
  # its own self-hosted runner and age key.
  truenas_input_servers = {
    for server_key, server in local.servers_model_desired : server_key => server
    if server.platform == "truenas"
  }

  # Expanded services targeting a TrueNAS server.
  truenas_input_services = {
    for service_key, service in local.services_model_desired : service_key => service
    if contains(keys(local.truenas_input_servers), service.target)
  }

  # Catalog app templates live beside each service with app-specific chart values.
  truenas_prepare_catalog_templates = {
    for service_key, service in local.truenas_input_services : service_key => {
      path = "${path.module}/services/${service.identity.service}/app.json.tftpl"
    }
    if fileexists("${path.module}/services/${service.identity.service}/app.json.tftpl")
  }

  # Encrypted GitHub files consumed by the TrueNAS deploy workflow.
  # Three categories are merged:
  #   1) Custom Docker Compose apps (rendered from docker-compose.yaml.tftpl)
  #   2) TrueNAS catalog apps (app.json.tftpl merged with service-specific values)
  #   3) Generic sidecar files (env, configs, etc. from services/{service}/)
  truenas_render_files = merge(
    {
      # 1) Custom Docker Compose apps
      for service_key, service in local.truenas_input_services : (
        "${service.target}/${service.identity.name}/compose.json"
        ) => {
        age_public_key = age_secret_key.server[service.target].public_key
        commit_message = "Update ${service_key} compose"
        content_type   = "json"
        file           = "${service.target}/${service.identity.name}/compose.json"

        content_base64 = sensitive(base64encode(templatefile(
          "${path.module}/templates/truenas/compose.json.tftpl",
          merge(local.services_render_context_final[service_key], {
            compose = local.services_render_files_compose[service_key]
          })
        )))
      }
      if contains(keys(local.services_render_files_compose), service_key)
    },
    {
      # 2) TrueNAS catalog apps — only when no custom compose file exists
      for service_key, service in local.truenas_input_services : (
        "${service.target}/${service.identity.name}/app.json"
        ) => {
        age_public_key = age_secret_key.server[service.target].public_key
        commit_message = "Update ${service_key} catalog app"
        content_type   = "json"
        file           = "${service.target}/${service.identity.name}/app.json"

        content_base64 = sensitive(base64encode(jsonencode(provider::deepmerge::mergo(
          jsondecode(templatefile(
            "${path.module}/templates/truenas/app.json.tftpl",
            local.services_render_context_final[service_key]
          )),
          jsondecode(templatefile(
            local.truenas_prepare_catalog_templates[service_key].path,
            local.services_render_context_final[service_key]
          ))
        ))))
      }
      if(
        !contains(keys(local.services_render_files_compose), service_key) &&
        contains(keys(local.truenas_prepare_catalog_templates), service_key)
      )
    },
    {
      # 3) Generic sidecar files (env, configs, etc.)
      for file_key, file_config in local.services_render_files_sidecars : (
        "${file_config.target}/${local.services_model_desired[file_config.stack].identity.name}/${file_config.rel_path}"
        ) => merge(file_config, {
          age_public_key = age_secret_key.server[file_config.target].public_key
          commit_message = "Update ${file_config.stack} ${file_config.rel_path}"
          file = (
            "${file_config.target}/${local.services_model_desired[file_config.stack].identity.name}/${file_config.rel_path}"
          )
      })
      if contains(keys(local.truenas_input_servers), file_config.target)
    }
  )

}

# GitHub secret names cannot contain hyphens, so the workflow matrix computes
# the same uppercase underscore form from the server key.
resource "github_actions_secret" "truenas_age_key" {
  for_each = local.truenas_input_servers

  plaintext_value = age_secret_key.server[each.key].secret_key
  repository      = local.defaults.github.repositories.truenas
  secret_name     = "AGE_KEY_${upper(replace(each.key, "-", "_"))}"
}

resource "github_repository_file" "truenas_deploy_request" {
  commit_message      = "Request changed deployments"
  file                = ".github/deploy-request.json"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas

  content = jsonencode({
    deployments = {
      for service_key, service in local.truenas_input_services : "${service.target}/${service.identity.name}" => sha256(jsonencode({
        sops = sha256(yamlencode({
          creation_rules = [
            for server_key, server in local.truenas_input_servers : {
              path_regex = "^${server_key}/"
              age        = age_secret_key.server[server_key].public_key
            }
          ]
        }))
        workflow = filesha256("${path.module}/templates/workflows/truenas-deploy.yml")

        files = {
          for file_key, file_config in local.truenas_render_files : file_config.file => nonsensitive(sha256(file_config.content_base64))
          if startswith(local.truenas_render_files[file_key].file, "${service.target}/${service.identity.name}/")
        }
      }))
    }
  })
}

resource "github_repository_file" "truenas_services_files" {
  for_each = local.truenas_render_files

  commit_message      = each.value.commit_message
  content             = module.sops_encrypt_truenas[each.key].encrypted_content
  file                = each.value.file
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas
}

module "sops_encrypt_truenas" {
  source   = "./modules/sops_encrypt"
  for_each = local.truenas_render_files

  age_public_key = each.value.age_public_key
  content_base64 = each.value.content_base64
  content_type   = each.value.content_type
  debug_path     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.truenas}/${each.key}" : ""
  filename       = each.value.file
}

resource "github_repository_file" "truenas_sops_config" {
  commit_message      = "Update SOPS configuration"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas

  content = yamlencode({
    creation_rules = [
      for server_key, server in local.truenas_input_servers : {
        path_regex = "^${server_key}/"
        age        = age_secret_key.server[server_key].public_key
      }
    ]
  })
}

resource "github_repository_file" "truenas_workflow_deploy" {
  commit_message      = "Update deploy workflow"
  content             = file("${path.module}/templates/workflows/truenas-deploy.yml")
  file                = ".github/workflows/deploy.yml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas
}

resource "terraform_data" "truenas_validation" {
  input = keys(local.truenas_input_services)

  lifecycle {
    # A TrueNAS service is either a custom app from docker-compose.yaml.tftpl
    # or a catalog app with app-specific values.
    precondition {
      condition = length([
        for service_key, service in local.truenas_input_services : service_key
        if !contains(keys(local.services_render_files_compose), service_key) &&
        !contains(keys(local.truenas_prepare_catalog_templates), service_key)
      ]) == 0
      error_message = "TrueNAS catalog services require services/{identity.service}/app.json.tftpl: ${join(", ", [
        for service_key, service in local.truenas_input_services : service_key
        if !contains(keys(local.services_render_files_compose), service_key) &&
        !contains(keys(local.truenas_prepare_catalog_templates), service_key)
      ])}"
    }
  }
}
