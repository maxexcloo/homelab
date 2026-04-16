locals {
  fly_service_env = {
    for k, v in local.fly_services : k => join("\n", [
      for field_name, field_value in v :
      "${upper(trimsuffix(field_name, "_sensitive"))}=${field_value}"
      if endswith(field_name, "_sensitive") && field_value != null && can(tostring(field_value)) && tostring(field_value) != ""
    ])
    if anytrue([
      for field_name, field_value in v :
      endswith(field_name, "_sensitive") && field_value != null && can(tostring(field_value)) && tostring(field_value) != ""
    ])
  }

  fly_service_files = {
    for pair in flatten([
      for k, v in local.fly_services : [
        for filepath in fileset(path.module, "templates/docker/${v.identity.service}/**") : {
          app_name     = v.app_name
          content      = templatefile("${path.module}/${filepath}", {
            app_name = v.app_name
            defaults = local.defaults
            servers  = local.servers
            service  = v
            services = local.services
          })
          content_type = can(regex("\\.toml$", filepath)) ? "toml" : can(regex("\\.(yaml|yml)$", filepath)) ? "yaml" : null
          rel_path     = trimprefix(filepath, "templates/docker/${v.identity.service}/")
          stack        = k
        }
        if !endswith(filepath, "docker-compose.yaml")
      ]
    ]) : "${pair.stack}/${pair.rel_path}" => pair
  }

  fly_services = {
    for k, v in local.services : k => merge(v, {
      app_name = "${v.identity.name}-${random_string.fly_service[k].result}"
    })
    if v.target == "fly"
  }

}

resource "github_actions_secret" "fly_age_key" {
  plaintext_value = age_secret_key.fly.secret_key
  repository      = local.defaults.github.repositories.fly
  secret_name     = "AGE_KEY"
}

resource "github_repository_file" "fly_service_env" {
  for_each = toset(nonsensitive(keys(local.fly_service_env)))

  commit_message      = "Update ${local.fly_services[each.key].app_name} secrets"
  content             = shell_sensitive_script.fly_service_env_encrypt[each.key].output["encrypted_content"]
  file                = "${local.fly_services[each.key].app_name}/.env"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly
}

resource "github_repository_file" "fly_service_files" {
  for_each = local.fly_service_files

  commit_message      = "Update ${each.value.app_name} ${each.value.rel_path}"
  content             = shell_sensitive_script.fly_service_files_encrypt[each.key].output["encrypted_content"]
  file                = "${each.value.app_name}/${each.value.rel_path}"
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

resource "github_repository_file" "fly_toml" {
  for_each = local.fly_services

  commit_message      = "Update ${each.value.app_name} Fly configuration"
  content             = shell_sensitive_script.fly_toml_encrypt[each.key].output["encrypted_content"]
  file                = "${each.value.app_name}/fly.toml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly
}

resource "random_string" "fly_service" {
  for_each = { for k, v in local.services : k => v if v.target == "fly" }

  length  = 6
  special = false
  upper   = false
}

resource "shell_sensitive_script" "fly_service_env_encrypt" {
  for_each = toset(nonsensitive(keys(local.fly_service_env)))

  environment = {
    AGE_PUBLIC_KEY = age_secret_key.fly.public_key
    CONTENT        = base64encode(local.fly_service_env[each.key])
    CONTENT_TYPE   = "dotenv"
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.fly}/${local.fly_services[each.key].identity.service}/.env" : ""
  }

  lifecycle_commands {
    create = local.sops_encrypt_script
    delete = "true"
    read   = local.sops_encrypt_script
    update = local.sops_encrypt_script
  }

  triggers = {
    age_public_key_hash = sha256(age_secret_key.fly.public_key)
    script_hash         = sha256(local.sops_encrypt_script)
  }
}

resource "shell_sensitive_script" "fly_service_files_encrypt" {
  for_each = local.fly_service_files

  environment = {
    AGE_PUBLIC_KEY = age_secret_key.fly.public_key
    CONTENT        = base64encode(each.value.content)
    CONTENT_TYPE   = each.value.content_type != null ? each.value.content_type : ""
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.fly}/${each.value.app_name}/${each.value.rel_path}" : ""
  }

  lifecycle_commands {
    create = local.sops_encrypt_script
    delete = "true"
    read   = local.sops_encrypt_script
    update = local.sops_encrypt_script
  }

  triggers = {
    age_public_key_hash = each.value.content_type != null ? sha256(age_secret_key.fly.public_key) : ""
    script_hash         = sha256(local.sops_encrypt_script)
  }
}

resource "shell_sensitive_script" "fly_toml_encrypt" {
  for_each = local.fly_services

  environment = {
    AGE_PUBLIC_KEY = age_secret_key.fly.public_key
    CONTENT        = base64encode(templatefile("${path.module}/templates/fly/fly.toml", {
      app_name = each.value.app_name
      defaults = local.defaults
      servers  = local.servers
      service  = each.value
      services = local.services
    }))
    CONTENT_TYPE = "toml"
    DEBUG_PATH   = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.fly}/${each.value.identity.service}/fly.toml" : ""
  }

  lifecycle_commands {
    create = local.sops_encrypt_script
    delete = "true"
    read   = local.sops_encrypt_script
    update = local.sops_encrypt_script
  }

  triggers = {
    age_public_key_hash = sha256(age_secret_key.fly.public_key)
    script_hash         = sha256(local.sops_encrypt_script)
  }
}
