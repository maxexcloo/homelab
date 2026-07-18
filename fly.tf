locals {
  # Expanded services whose deployment target is Fly.io.
  _fly_services = {
    for service_key, service in local.services_model : service_key => service
    if(
      service.target == "fly" &&
      service.identity.service != null
    )
  }

  # GitHub files written to the Fly deployment repository. Four categories:
  #   1) fly.toml — main app configuration
  #   2) .certs — custom domain certificate hostnames
  #   3) .machine-count — desired machine count
  #   4) Sidecar files (env, configs, etc. from services/{service}/)
  _fly_render_files = merge(
    {
      # 1) Main Fly app configuration
      for service_key, service in local._fly_services : "${service.fly.app_name}/fly.toml" => {
        commit_message = "Update ${service.fly.app_name} configuration"
        file           = "${service.fly.app_name}/fly.toml"

        content_base64 = sensitive(
          base64encode(
            templatefile(
              "${path.module}/templates/fly/fly.toml.tftpl",
              local.services_render_template_context[service_key],
            ),
          ),
        )
      }
    },
    {
      # 2) Custom domain certificate hostnames
      for service_key, service in local._fly_services : "${service.fly.app_name}/.certs" => {
        commit_message = "Update ${service.fly.app_name} certificate hostnames"
        file           = "${service.fly.app_name}/.certs"

        content_base64 = base64encode(
          templatefile(
            "${path.module}/templates/fly/certs.tftpl",
            local.services_render_template_context[service_key],
          ),
        )
      }
      if length([
        for route in service.routing.urls : route
        if route.url != null
      ]) > 0
    },
    {
      # 3) Machine count for scaling
      for service in values(local._fly_services) : "${service.fly.app_name}/.machine-count" => {
        commit_message = "Update ${service.fly.app_name} machine count"
        content_base64 = base64encode("${service.fly.machine_count}\n")
        file           = "${service.fly.app_name}/.machine-count"
      }
      if service.fly.machine_count != null
    },
    {
      # 4) Generic sidecar files (env, configs, etc.)
      for file_config in values(local.services_render_write_sidecars) : "${local._fly_services[file_config.stack].fly.app_name}/${file_config.rel_path}" => merge(
        file_config,
        {
          commit_message = "Update ${file_config.stack} ${file_config.rel_path}"
          file           = "${local._fly_services[file_config.stack].fly.app_name}/${file_config.rel_path}"
        },
      )
      if file_config.target == "fly"
    }
  )
}

# Shared age key for the Fly deployment repository; per-service files are
# separated by directory rather than by recipient key.
resource "github_actions_secret" "fly_age_key" {
  repository  = github_repository.deployment["fly"].name
  secret_name = "AGE_KEY"
  value       = age_secret_key.fly.secret_key
}

resource "github_repository_file" "fly_deploy_request" {
  commit_message      = "Request changed deployments"
  file                = ".github/deploy-request.json"
  overwrite_on_create = true
  repository          = github_repository.deployment["fly"].name

  content = jsonencode({
    workflow_revision = local.github_workflow_revisions.fly

    deployments = {
      for service in values(local._fly_services) : service.fly.app_name => sha256(jsonencode({
        files = {
          for file_config in values(local._fly_render_files) : file_config.file => nonsensitive(sha256(file_config.content_base64))
          if startswith(file_config.file, "${service.fly.app_name}/")
        }

        sops = sha256(age_secret_key.fly.public_key)
      }))
    }
  })

  depends_on = [
    github_repository_file.fly_sops_config,
    github_repository_file.workflow_file,
    module.encrypted_github_file_fly,
  ]
}

module "encrypted_github_file_fly" {
  for_each = toset(nonsensitive(keys(local._fly_render_files)))
  source   = "./modules/github_file_encrypted"

  age_public_key = age_secret_key.fly.public_key
  commit_message = local._fly_render_files[each.key].commit_message
  content_base64 = local._fly_render_files[each.key].content_base64
  content_type   = "binary"
  debug_path     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.deployment_repositories.fly.name}/${each.key}" : ""
  file           = local._fly_render_files[each.key].file
  repository     = github_repository.deployment["fly"].name
}

resource "github_repository_file" "fly_sops_config" {
  commit_message      = "Update SOPS configuration"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = github_repository.deployment["fly"].name

  content = yamlencode({
    creation_rules = [
      {
        age = age_secret_key.fly.public_key
      }
    ]
  })
}
