locals {
  komodo_stacks = {
    for k, v in local.services : k => v
    if contains(keys(local.servers), v.target) &&
    local.servers[v.target].features.docker &&
    contains(keys(local.services_compose), k)
  }
}

resource "github_repository_file" "komodo_resource_sync" {
  commit_message      = "Update Komodo ResourceSync configuration"
  file                = "resource_sync.toml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo

  content = templatefile("${path.module}/templates/komodo/resource_sync.toml", {
    github_user = data.github_user.default.login
    repository  = local.defaults.github.repositories.komodo
  })
}

resource "github_repository_file" "komodo_servers" {
  commit_message      = "Update Komodo server configurations"
  file                = "servers.toml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo

  content = templatefile("${path.module}/templates/komodo/servers.toml", {
    servers = local.servers
  })
}

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

  content = templatefile("${path.module}/templates/komodo/stacks.toml", {
    github_user = data.github_user.default.login
    repository  = local.defaults.github.repositories.komodo
    stacks      = local.komodo_stacks
  })
}

resource "github_repository_file" "komodo_stacks_compose" {
  for_each = local.komodo_stacks

  commit_message      = "Update ${each.key} SOPS-encrypted compose"
  content             = shell_sensitive_script.komodo_stacks_compose_encrypt[each.key].output["encrypted_content"]
  file                = "${each.key}/compose.yaml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo
}

resource "github_repository_file" "komodo_stacks_config" {
  for_each = {
    for k, v in local.services_files : k => v
    if contains(keys(local.servers), v.target) && local.servers[v.target].features.docker
  }

  commit_message      = "Update ${each.value.stack} config"
  content             = shell_sensitive_script.service_file_encrypt[each.key].output["encrypted_content"]
  file                = each.key
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo
}

resource "shell_sensitive_script" "komodo_stacks_compose_encrypt" {
  for_each = local.komodo_stacks

  environment = {
    AGE_PUBLIC_KEY = local.servers[each.value.target].age_public_key
    CONTENT        = sensitive(base64encode(local.services_compose[each.key]))
    CONTENT_TYPE   = "yaml"
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.komodo}/${each.key}/compose.yaml" : ""
  }

  lifecycle_commands {
    create = sensitive(local.sops_encrypt_script)
    delete = "true"
    read   = sensitive(local.sops_encrypt_script)
    update = sensitive(local.sops_encrypt_script)
  }

  triggers = {
    age_public_key_hash = sha256(local.servers[each.value.target].age_public_key)
    script_hash         = sha256(local.sops_encrypt_script)
  }
}
