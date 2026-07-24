# Fly deploys share one repository key because app files are isolated by app
# directory in the deploy repository.
resource "github_actions_secret" "fly_age_key" {
  repository  = var.integrations.github.repositories.fly
  secret_name = "AGE_KEY"
  value       = age_secret_key.fly.secret_key
}

resource "github_repository_file" "fly_sops_config" {
  commit_message      = "Update SOPS configuration"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = var.integrations.github.repositories.fly

  content = yamlencode({
    creation_rules = [
      {
        age = age_secret_key.fly.public_key
      }
    ]
  })
}

module "encrypted_github_file_fly" {
  for_each = local._fly_render_file_keys
  source   = "../github_file_encrypted"

  age_public_key = age_secret_key.fly.public_key
  commit_message = local._fly_render_files[each.key].commit_message
  content_base64 = local._fly_render_files[each.key].content_base64
  content_type   = "binary"
  debug_path     = var.integrations.debug_dir != "" ? "${var.integrations.debug_dir}/${var.integrations.github.repositories.fly}/${each.key}" : ""
  file           = local._fly_render_files[each.key].file
  repository     = var.integrations.github.repositories.fly
}

resource "github_repository_file" "fly_deploy_request" {
  commit_message      = "Request changed deployments"
  file                = ".github/deploy-request.json"
  overwrite_on_create = true
  repository          = var.integrations.github.repositories.fly

  content = jsonencode({
    workflow_revision = var.integrations.github.workflow_revisions.fly

    deployments = {
      for service in values(local._fly_services) : service.fly.app_name => sha256(jsonencode({
        sops = sha256(age_secret_key.fly.public_key)

        files = {
          for file_config in values(local._fly_render_files) : file_config.file => nonsensitive(sha256(file_config.content_base64))
          if startswith(file_config.file, "${service.fly.app_name}/")
        }
      }))
    }
  })

  depends_on = [
    github_repository_file.fly_sops_config,
    module.encrypted_github_file_fly,
  ]
}
