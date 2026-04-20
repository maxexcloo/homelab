locals {
  # Komodo only receives services with a rendered compose file on Docker-capable
  # server targets.
  komodo_input_stacks = {
    for k, v in local.services_model_desired : k => v
    if contains(keys(local.servers_model_desired), v.target) &&
    local.servers_model_desired[v.target].features.docker &&
    contains(keys(local.services_rendered_compose), k)
  }

  # Encrypted GitHub files consumed by Komodo ResourceSync. Service sidecar files
  # reuse the same relative paths as the service artifact model.
  komodo_render_files = merge(
    {
      for k, v in local.komodo_input_stacks : "${k}/compose.yaml" => {
        age_public_key = age_secret_key.server[v.target].public_key
        commit_message = "Update ${k} compose"
        content_base64 = sensitive(base64encode(local.services_rendered_compose[k]))
        content_type   = "yaml"
        file           = "${k}/compose.yaml"
      }
    },
    {
      for k, v in local.services_rendered_files : k => merge(v, {
        age_public_key = age_secret_key.server[v.target].public_key
        commit_message = "Update ${v.stack} ${v.rel_path}"
        file           = k
      })
      if contains(keys(local.servers_model_desired), v.target) && local.servers_model_desired[v.target].features.docker
    }
  )
}

resource "github_repository_file" "komodo_resource_sync" {
  commit_message      = "Update Komodo ResourceSync configuration"
  file                = "resource_sync.toml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo

  content = templatefile("${path.module}/templates/komodo/resource_sync.toml.tftpl", {
    github_user = data.github_user.default.login
    repository  = local.defaults.github.repositories.komodo
  })
}

resource "github_repository_file" "komodo_servers" {
  commit_message      = "Update Komodo server configurations"
  file                = "servers.toml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo

  content = sensitive(templatefile("${path.module}/templates/komodo/servers.toml.tftpl", {
    servers = local.servers_model_desired
  }))
}

# Per-stack SOPS rules let each target server decrypt only the stacks assigned
# to it.
resource "github_repository_file" "komodo_sops_config" {
  commit_message      = "Update SOPS configuration"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo

  content = join("\n", concat(
    ["creation_rules:"],
    [for k, v in local.komodo_input_stacks : "  - path_regex: '^${k}/'\n    age: ${age_secret_key.server[v.target].public_key}"]
  ))
}

resource "github_repository_file" "komodo_stacks" {
  commit_message      = "Update Komodo stack configurations"
  file                = "stacks.toml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo

  content = templatefile("${path.module}/templates/komodo/stacks.toml.tftpl", {
    github_user = data.github_user.default.login
    repository  = local.defaults.github.repositories.komodo
    stacks      = local.komodo_input_stacks
  })
}

resource "github_repository_file" "komodo_stacks_files" {
  for_each = local.komodo_render_files

  commit_message      = each.value.commit_message
  content             = shell_sensitive_script.komodo_stacks_files_encrypt[each.key].output["encrypted_content"]
  file                = each.value.file
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo
}

resource "shell_sensitive_script" "komodo_stacks_files_encrypt" {
  for_each = local.komodo_render_files

  # The script receives base64 content and returns encrypted text for GitHub.
  # DEBUG_PATH intentionally writes plaintext only when explicitly configured.
  environment = {
    AGE_PUBLIC_KEY = each.value.age_public_key
    CONTENT        = sensitive(each.value.content_base64)
    CONTENT_TYPE   = each.value.content_type
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.komodo}/${each.key}" : ""
    FILENAME       = each.value.file
  }

  lifecycle_commands {
    create = sensitive(local.script_sops_encrypt)
    delete = "true"
    read   = sensitive(local.script_sops_encrypt)
    update = sensitive(local.script_sops_encrypt)
  }

  triggers = {
    age_public_key_hash = sha256(each.value.age_public_key)
    script_hash         = sha256(local.script_sops_encrypt)
  }
}
