resource "github_repository_file" "truenas_sops_config" {
  commit_message      = "Update SOPS configuration"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = var.integrations.github.repositories.truenas

  content = yamlencode({
    creation_rules = [
      for server_key in sort(keys(local.truenas_servers)) : {
        age        = var.servers.age_public_keys[server_key]
        path_regex = "^${server_key}/"
      }
    ]
  })
}

module "encrypted_github_file_truenas" {
  for_each = local._truenas_render_file_keys
  source   = "../github_file_encrypted"

  age_public_key = local._truenas_render_files[each.key].age_public_key
  commit_message = local._truenas_render_files[each.key].commit_message
  content_base64 = local._truenas_render_files[each.key].content_base64
  content_type   = local._truenas_render_files[each.key].content_type
  debug_path     = var.integrations.debug_dir != "" ? "${var.integrations.debug_dir}/${var.integrations.github.repositories.truenas}/${each.key}" : ""
  file           = local._truenas_render_files[each.key].file
  repository     = var.integrations.github.repositories.truenas
}

resource "github_repository_file" "truenas_deploy_request" {
  commit_message      = "Request changed deployments"
  file                = ".github/deploy-request.json"
  overwrite_on_create = true
  repository          = var.integrations.github.repositories.truenas

  content = jsonencode({
    workflow_revision = var.integrations.github.workflow_revisions.truenas

    deployments = {
      for service in values(local.truenas_services) : "${service.target}/${service.identity.name}" => {
        files = sort([
          for file_key in local._truenas_render_file_keys : file_key
          if startswith(file_key, "${service.target}/${service.identity.name}/")
        ])

        hash = sha256(jsonencode({
          sops = sha256(var.servers.age_public_keys[service.target])

          files = {
            for file_config in values(local._truenas_render_files) : file_config.file => nonsensitive(sha256(file_config.content_base64))
            if startswith(file_config.file, "${service.target}/${service.identity.name}/")
          }
        }))
      }
    }
  })

  depends_on = [
    github_repository_file.truenas_sops_config,
    module.encrypted_github_file_truenas,
  ]
}
