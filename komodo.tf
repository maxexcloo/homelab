locals {
  # Komodo only receives services with a rendered compose file on Docker-capable
  # server targets.
  komodo_stacks = {
    for k, v in local.services : k => v
    if contains(keys(local.servers), v.target) &&
    local.servers[v.target].features.docker &&
    contains(keys(local.services_compose), k)
  }

  komodo_stacks_file = merge(
    {
      for k, v in local.komodo_stacks : "${k}/compose.yaml" => {
        age_public_key = local.servers[v.target].age_public_key
        commit_message = "Update ${k} compose"
        content_base64 = sensitive(base64encode(local.services_compose[k]))
        content_type   = "yaml"
        file           = "${k}/compose.yaml"
      }
    },
    {
      for k, v in local.services_files : k => merge(v, {
        age_public_key = local.servers[v.target].age_public_key
        commit_message = "Update ${v.stack} ${v.rel_path}"
        file           = k
      })
      if contains(keys(local.servers), v.target) && local.servers[v.target].features.docker
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

  content = templatefile("${path.module}/templates/komodo/servers.toml.tftpl", {
    servers = local.servers
  })
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
    [for k, v in local.komodo_stacks : "  - path_regex: '^${k}/'\n    age: ${age_secret_key.server[v.target].public_key}"]
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
    stacks      = local.komodo_stacks
  })
}

resource "github_repository_file" "komodo_stacks_file" {
  for_each = local.komodo_stacks_file

  commit_message      = each.value.commit_message
  content             = shell_sensitive_script.komodo_stacks_file_encrypt[each.key].output["encrypted_content"]
  file                = each.value.file
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo
}

resource "shell_sensitive_script" "komodo_stacks_file_encrypt" {
  for_each = local.komodo_stacks_file

  environment = {
    AGE_PUBLIC_KEY = each.value.age_public_key
    CONTENT        = sensitive(each.value.content_base64)
    CONTENT_TYPE   = each.value.content_type
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.komodo}/${each.key}" : ""
    FILENAME       = each.value.file
  }

  lifecycle_commands {
    create = sensitive(local.sops_encrypt_script)
    delete = "true"
    read   = sensitive(local.sops_encrypt_script)
    update = sensitive(local.sops_encrypt_script)
  }

  triggers = {
    age_public_key_hash = sha256(each.value.age_public_key)
    script_hash         = sha256(local.sops_encrypt_script)
  }
}
