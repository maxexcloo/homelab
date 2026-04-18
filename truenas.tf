locals {
  # TrueNAS deploy artifacts are grouped by target server because each server has
  # its own self-hosted runner and age key.
  truenas_servers = {
    for k, v in local.servers : k => v
    if v.platform == "truenas"
  }

  truenas_services = {
    for k, v in local.services : k => v
    if contains(keys(local.truenas_servers), v.target)
  }
}

# GitHub secret names cannot contain hyphens, so the workflow matrix computes
# the same uppercase underscore form from the server key.
resource "github_actions_secret" "truenas_age_key" {
  for_each = local.truenas_servers

  plaintext_value = age_secret_key.server[each.key].secret_key
  repository      = local.defaults.github.repositories.truenas
  secret_name     = "AGE_KEY_${upper(replace(each.key, "-", "_"))}"
}

resource "github_repository_file" "truenas_services_compose" {
  for_each = {
    for k, v in local.truenas_services : k => v
    if contains(keys(local.services_compose), k)
  }

  commit_message      = "Update ${each.key} compose"
  content             = shell_sensitive_script.truenas_services_compose_encrypt[each.key].output["encrypted_content"]
  file                = "${each.value.target}/${each.value.identity.service}/compose.json"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas
}

resource "github_repository_file" "truenas_services_config" {
  for_each = {
    for k, v in local.services_files : k => v
    if contains(keys(local.truenas_servers), v.target)
  }

  commit_message      = "Update ${each.value.stack} ${each.value.rel_path}"
  content             = shell_sensitive_script.service_file_encrypt[each.key].output["encrypted_content"]
  file                = "${each.value.target}/${each.value.service_name}/${each.value.rel_path}"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas
}

resource "github_repository_file" "truenas_services_override" {
  for_each = {
    for k, v in local.truenas_services : k => v
    if !contains(keys(local.services_compose), k)
  }

  commit_message      = "Update ${each.key} overrides"
  content             = shell_sensitive_script.truenas_services_override_encrypt[each.key].output["encrypted_content"]
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

resource "github_repository_file" "truenas_workflow_deploy" {
  commit_message      = "Update deploy workflow"
  content             = file("${path.module}/templates/workflows/truenas-deploy.yml")
  file                = ".github/workflows/deploy.yml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas
}

# TrueNAS custom apps consume a JSON wrapper whose compose content is embedded
# as a string.
resource "shell_sensitive_script" "truenas_services_compose_encrypt" {
  for_each = {
    for k, v in local.truenas_services : k => v
    if contains(keys(local.services_compose), k)
  }

  environment = {
    AGE_PUBLIC_KEY = local.servers[each.value.target].age_public_key
    CONTENT_TYPE   = "json"
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.truenas}/${each.value.target}/${each.value.identity.service}/compose.json" : ""

    CONTENT = sensitive(base64encode(jsonencode({
      app_name                     = each.value.identity.service
      custom_app                   = true
      custom_compose_config_string = local.services_compose[each.key]
    })))
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

# Services without a compose template use a TrueNAS override file to update the
# chart's environment and labels.
resource "shell_sensitive_script" "truenas_services_override_encrypt" {
  for_each = {
    for k, v in local.truenas_services : k => v
    if !contains(keys(local.services_compose), k)
  }

  environment = {
    AGE_PUBLIC_KEY = local.servers[each.value.target].age_public_key
    CONTENT_TYPE   = "json"
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.truenas}/${each.value.target}/${each.value.identity.service}/${each.value.identity.service}/override.json" : ""

    CONTENT = sensitive(base64encode(jsonencode({
      values = {
        containerConfig = {
          environment = local.services_env[each.key]
          labels      = local.services_labels[each.key]
        }
      }
    })))
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
