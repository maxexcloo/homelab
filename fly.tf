locals {
  _services_fly_computed = {
    for k, v in local._services_computed : k => {
      fqdn_external = "${coalesce(v.platform_config.fly.app_name, "${v.identity.name}-${random_string.fly_service[k].result}")}.fly.dev"
      networking = merge(v.networking, {
        urls = distinct(concat(v.networking.urls, ["${coalesce(v.platform_config.fly.app_name, "${v.identity.name}-${random_string.fly_service[k].result}")}.fly.dev"]))
      })
      platform_config = merge(v.platform_config, {
        fly = merge(v.platform_config.fly, {
          app_name = coalesce(v.platform_config.fly.app_name, "${v.identity.name}-${random_string.fly_service[k].result}")
        })
      })
    }
    if v.target == "fly"
  }

  fly_services = {
    for k, v in local.services : k => v
    if v.target == "fly"
  }

  fly_services_env = {
    for k, env in local.fly_services_env_vars : k => join("\n", [
      for field_name in sort(nonsensitive(keys(env))) :
      "${field_name}=${env[field_name]}"
    ])
    if length(nonsensitive(keys(env))) > 0
  }

  fly_services_env_vars = {
    for k, v in local.fly_services : k => merge(
      local.services_env[k],
      {
        for sensitive_field_name, sensitive_field_value in v :
        upper(trimsuffix(sensitive_field_name, "_sensitive")) => sensitive_field_value
        if endswith(sensitive_field_name, "_sensitive") && sensitive_field_value != null && can(tostring(sensitive_field_value)) && tostring(sensitive_field_value) != ""
      }
    )
  }
}

resource "github_actions_secret" "fly_age_key" {
  plaintext_value = age_secret_key.fly.secret_key
  repository      = local.defaults.github.repositories.fly
  secret_name     = "AGE_KEY"
}

resource "github_repository_file" "fly_services_cert" {
  for_each = {
    for k, v in local.fly_services : k => v
    if length([for url in v.networking.urls : url if url != v.fqdn_external]) > 0
  }

  commit_message      = "Update ${each.value.platform_config.fly.app_name} certificate hostnames"
  content             = join("\n", [for url in each.value.networking.urls : url if url != each.value.fqdn_external])
  file                = "${each.value.platform_config.fly.app_name}/.certs"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly
}

resource "github_repository_file" "fly_services_env" {
  for_each = toset(nonsensitive(keys(local.fly_services_env)))

  commit_message      = "Update ${local.fly_services[each.key].platform_config.fly.app_name} secrets"
  content             = shell_sensitive_script.fly_services_env_encrypt[each.key].output["encrypted_content"]
  file                = "${local.fly_services[each.key].platform_config.fly.app_name}/.env"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly
}

resource "github_repository_file" "fly_services_file" {
  for_each = {
    for k, v in local.services_files : k => v
    if v.target == "fly"
  }

  commit_message      = "Update ${local.fly_services[each.value.stack].platform_config.fly.app_name} ${each.value.rel_path}"
  content             = shell_sensitive_script.service_file_encrypt[each.key].output["encrypted_content"]
  file                = "${local.fly_services[each.value.stack].platform_config.fly.app_name}/${each.value.rel_path}"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly
}

resource "github_repository_file" "fly_services_toml" {
  for_each = local.fly_services

  commit_message      = "Update ${each.value.platform_config.fly.app_name} Fly configuration"
  content             = shell_sensitive_script.fly_services_toml_encrypt[each.key].output["encrypted_content"]
  file                = "${each.value.platform_config.fly.app_name}/fly.toml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly
}

resource "github_repository_file" "fly_sops_config" {
  commit_message      = "Update SOPS configuration"
  content             = "creation_rules:\n  - age: ${age_secret_key.fly.public_key}\n"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly
}

resource "github_repository_file" "fly_workflow_deploy" {
  commit_message      = "Update deploy workflow"
  content             = file("${path.module}/templates/workflows/fly-deploy.yml")
  file                = ".github/workflows/deploy.yml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly
}

resource "random_string" "fly_service" {
  for_each = {
    for k, v in local._services_computed : k => v
    if v.target == "fly"
  }

  length  = 6
  special = false
  upper   = false
}

resource "shell_sensitive_script" "fly_services_env_encrypt" {
  for_each = toset(nonsensitive(keys(local.fly_services_env)))

  environment = {
    AGE_PUBLIC_KEY = age_secret_key.fly.public_key
    CONTENT        = sensitive(base64encode(local.fly_services_env[each.key]))
    CONTENT_TYPE   = "dotenv"
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.fly}/${local.fly_services[each.key].identity.service}/.env" : ""
  }

  lifecycle_commands {
    create = sensitive(local.sops_encrypt_script)
    delete = "true"
    read   = sensitive(local.sops_encrypt_script)
    update = sensitive(local.sops_encrypt_script)
  }

  triggers = {
    age_public_key_hash = sha256(age_secret_key.fly.public_key)
    script_hash         = sha256(local.sops_encrypt_script)
  }
}

resource "shell_sensitive_script" "fly_services_toml_encrypt" {
  for_each = local.fly_services

  environment = {
    AGE_PUBLIC_KEY = age_secret_key.fly.public_key
    CONTENT        = sensitive(base64encode(templatefile("${path.module}/templates/fly/fly.toml", local.services_template_vars[each.key])))
    CONTENT_TYPE   = "toml"
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.fly}/${each.value.identity.service}/fly.toml" : ""
  }

  lifecycle_commands {
    create = sensitive(local.sops_encrypt_script)
    delete = "true"
    read   = sensitive(local.sops_encrypt_script)
    update = sensitive(local.sops_encrypt_script)
  }

  triggers = {
    age_public_key_hash = sha256(age_secret_key.fly.public_key)
    script_hash         = sha256(local.sops_encrypt_script)
  }
}
