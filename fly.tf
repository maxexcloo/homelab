locals {
  # Expanded services whose deployment target is Fly.io.
  fly_input_services = {
    for service_key, service in local.services_model : service_key => service
    if service.target == "fly"
  }

  # GitHub files written to the Fly deployment repository. Four categories:
  #   1) fly.toml — main app configuration
  #   2) .certs — custom domain certificate hostnames
  #   3) .machine-count — desired machine count
  #   4) Sidecar files (env, configs, etc. from services/{service}/)
  fly_render_files = merge(
    {
      # 1) Main Fly app configuration
      for service_key, service in local.fly_input_services : (
        "${service.fly.app_name}/fly.toml"
        ) => {
        commit_message = "Update ${service.fly.app_name} configuration"
        file           = "${service.fly.app_name}/fly.toml"

        content_base64 = sensitive(base64encode(templatefile(
          "${path.module}/templates/fly/fly.toml.tftpl",
          local.services_render_context[service_key]
        )))
      }
    },
    {
      # 2) Custom domain certificate hostnames
      for service_key, service in local.fly_input_services : (
        "${service.fly.app_name}/.certs"
        ) => {
        commit_message = "Update ${service.fly.app_name} certificate hostnames"
        file           = "${service.fly.app_name}/.certs"

        content_base64 = base64encode(templatefile(
          "${path.module}/templates/fly/certs.tftpl",
          local.services_render_context[service_key]
        ))
      }
      if length(service.routing.urls) > 0
    },
    {
      # 3) Machine count for scaling
      for service_key, service in local.fly_input_services : (
        "${service.fly.app_name}/.machine-count"
        ) => {
        commit_message = "Update ${service.fly.app_name} machine count"
        content_base64 = base64encode("${service.fly.machine_count}\n")
        file           = "${service.fly.app_name}/.machine-count"
      }
      if service.fly.machine_count != null
    },
    {
      # 4) Generic sidecar files (env, configs, etc.)
      for file_key, file_config in local.services_render_files_sidecars : (
        "${local.fly_input_services[file_config.stack].fly.app_name}/${file_config.rel_path}"
        ) => merge(file_config, {
          commit_message = "Update ${file_config.stack} ${file_config.rel_path}"
          file           = "${local.fly_input_services[file_config.stack].fly.app_name}/${file_config.rel_path}"
      })
      if file_config.target == "fly"
    }
  )
}

# Shared age key for the Fly deployment repository; per-service files are
# separated by directory rather than by recipient key.
resource "github_actions_secret" "fly_age_key" {
  plaintext_value = age_secret_key.fly.secret_key
  repository      = local.defaults.github.repositories.fly
  secret_name     = "AGE_KEY"
}

resource "github_repository_file" "fly_deploy_request" {
  commit_message      = "Request changed deployments"
  file                = ".github/deploy-request.json"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly

  content = jsonencode({
    deployments = {
      for service_key, service in local.fly_input_services : service.fly.app_name => sha256(jsonencode({
        sops = sha256(yamlencode({
          creation_rules = [
            {
              age = age_secret_key.fly.public_key
            }
          ]
        }))
        workflow = filesha256("${path.module}/templates/workflows/fly-deploy.yml")

        files = {
          for file_key, file_config in local.fly_render_files : file_config.file => nonsensitive(sha256(file_config.content_base64))
          if startswith(local.fly_render_files[file_key].file, "${service.fly.app_name}/")
        }
      }))
    }
  })
}

module "encrypted_github_file_fly" {
  source   = "./modules/github_file_encrypted"
  for_each = local.fly_render_files

  age_public_key = age_secret_key.fly.public_key
  commit_message = each.value.commit_message
  content_base64 = each.value.content_base64
  content_type   = "binary"
  debug_path     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.fly}/${each.key}" : ""
  file           = each.value.file
  repository     = local.defaults.github.repositories.fly
}

resource "github_repository_file" "fly_sops_config" {
  commit_message      = "Update SOPS configuration"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly

  content = yamlencode({
    creation_rules = [
      {
        age = age_secret_key.fly.public_key
      }
    ]
  })
}

resource "github_repository_file" "fly_workflow_deploy" {
  commit_message      = "Update deploy workflow"
  content             = file("${path.module}/templates/workflows/fly-deploy.yml")
  file                = ".github/workflows/deploy.yml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly
}
