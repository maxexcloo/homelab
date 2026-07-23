resource "github_repository_file" "docker_sops_config" {
  commit_message      = "Update SOPS configuration"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = var.integrations.github.repositories.docker

  content = yamlencode({
    creation_rules = [
      for server_key in sort(keys(local._docker_servers)) : {
        age        = var.servers.age_public_keys[server_key]
        path_regex = "^${server_key}/"
      }
    ]
  })
}

module "encrypted_github_file_docker" {
  for_each = local._docker_render_file_keys
  source   = "../github_file_encrypted"

  age_public_key = local._docker_render_files[each.key].age_public_key
  commit_message = local._docker_render_files[each.key].commit_message
  content_base64 = local._docker_render_files[each.key].content_base64
  content_type   = local._docker_render_files[each.key].content_type
  debug_path     = var.integrations.debug_dir != "" ? "${var.integrations.debug_dir}/${var.integrations.github.repositories.docker}/${each.key}" : ""
  encrypt        = local._docker_render_files[each.key].encrypt
  file           = local._docker_render_files[each.key].file
  repository     = var.integrations.github.repositories.docker
}
