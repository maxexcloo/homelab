locals {
  truenas_servers = {
    for k, v in local.servers : k => v
    if v.platform == "truenas"
  }

  truenas_service_config = {
    for k, v in local.service_config_files : k => v
    if contains(keys(local.truenas_servers), v.target)
  }

  truenas_services = {
    for k, v in local.services : k => v
    if contains(keys(local.truenas_servers), v.target)
  }
}

resource "github_actions_secret" "truenas_age_key" {
  for_each = local.truenas_servers

  plaintext_value = age_secret_key.server[each.key].secret_key
  repository      = local.defaults.github.repositories.truenas
  secret_name     = "AGE_KEY_${upper(replace(each.key, "-", "_"))}"
}

resource "github_repository_file" "truenas_compose" {
  for_each = { for k, v in local.truenas_services : k => v
  if fileexists("${path.module}/templates/docker/${v.identity.service}/docker-compose.yaml") }

  commit_message      = "Update ${each.key} compose"
  content             = shell_sensitive_script.truenas_compose_encrypt[each.key].output["encrypted_content"]
  file                = "${each.value.target}/${each.value.identity.service}/compose.json"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas
}

resource "github_repository_file" "truenas_service_config" {
  for_each = local.truenas_service_config

  commit_message      = "Update ${each.value.stack} ${each.value.rel_path}"
  content             = shell_sensitive_script.service_config_encrypt[each.key].output["encrypted_content"]
  file                = "${each.value.target}/${each.value.service_name}/${each.value.rel_path}"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas
}

resource "github_repository_file" "truenas_service_standard_overrides" {
  for_each = { for k, v in local.truenas_services : k => v
  if !fileexists("${path.module}/templates/docker/${v.identity.service}/docker-compose.yaml") }

  commit_message      = "Update ${each.key} overrides"
  content             = shell_sensitive_script.truenas_service_standard_overrides_encrypt[each.key].output["encrypted_content"]
  file                = "${each.value.target}/${each.value.identity.service}/${each.value.identity.service}/override.json"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas
}

resource "github_repository_file" "truenas_sops_config" {
  commit_message      = "Update SOPS configuration"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas

  content = join("\n", concat(
    ["creation_rules:"],
    [for k, v in local.truenas_servers : "  - path_regex: '^${k}/'\n    age: ${age_secret_key.server[k].public_key}"]
  ))
}

resource "shell_sensitive_script" "truenas_compose_encrypt" {
  for_each = { for k, v in local.truenas_services : k => v
  if fileexists("${path.module}/templates/docker/${v.identity.service}/docker-compose.yaml") }

  environment = {
    AGE_PUBLIC_KEY = local.servers[each.value.target].age_public_key
    CONTENT_TYPE   = "json"
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.truenas}/${each.value.target}/${each.value.identity.service}/compose.json" : ""

    CONTENT = base64encode(jsonencode({
      app_name   = each.value.identity.service
      custom_app = true

      custom_compose_config_string = templatefile("${path.module}/templates/docker/${each.value.identity.service}/docker-compose.yaml", {
        defaults = local.defaults
        env      = local.service_env[each.key]
        labels   = local.service_labels[each.key]
        server   = local.servers[each.value.target]
        servers  = local.servers
        service  = each.value
        services = local.services
      })
    }))
  }

  lifecycle_commands {
    create = local.sops_encrypt_script
    delete = "true"
    read   = local.sops_encrypt_script
    update = local.sops_encrypt_script
  }

  triggers = {
    age_public_key_hash = sha256(local.servers[each.value.target].age_public_key)
    script_hash         = sha256(local.sops_encrypt_script)
  }
}

resource "shell_sensitive_script" "truenas_service_standard_overrides_encrypt" {
  for_each = { for k, v in local.truenas_services : k => v
  if !fileexists("${path.module}/templates/docker/${v.identity.service}/docker-compose.yaml") }

  environment = {
    AGE_PUBLIC_KEY = local.servers[each.value.target].age_public_key
    CONTENT_TYPE   = "json"
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.truenas}/${each.value.target}/${each.value.identity.service}/${each.value.identity.service}/override.json" : ""

    CONTENT = base64encode(jsonencode({
      values = {
        containerConfig = {
          labels = local.service_labels[each.key]
        }
      }
    }))
  }

  lifecycle_commands {
    create = local.sops_encrypt_script
    delete = "true"
    read   = local.sops_encrypt_script
    update = local.sops_encrypt_script
  }

  triggers = {
    age_public_key_hash = sha256(local.servers[each.value.target].age_public_key)
    script_hash         = sha256(local.sops_encrypt_script)
  }
}
