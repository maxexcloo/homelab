locals {
  fly_service_configs = {
    for pair in flatten([
      for k, v in local.fly_services : [
        for filepath in fileset(path.module, "templates/${v.identity.service}/*.yaml") : {
          content = templatefile("${path.module}/${filepath}", {
            defaults = local.defaults
            servers  = local.servers
            service  = v
            services = local.services
          })
          filename = basename(filepath)
          stack    = k
        }
      ]
    ]) : "${pair.stack}/${pair.filename}" => pair
  }

  fly_services = {
    for k, v in local.services : k => v
    if v.server == "fly"
  }

  fly_toml_content = {
    for k, v in local.fly_services : k => templatefile("${path.module}/templates/fly/fly.toml", {
      defaults = local.defaults
      servers  = local.servers
      service  = v
      services = local.services
    })
  }
}

resource "github_actions_secret" "fly_age_key" {
  plaintext_value = age_secret_key.fly.secret_key
  repository      = local.defaults.github.repositories.fly
  secret_name     = "AGE_KEY"
}

resource "github_repository_file" "fly_service_configs" {
  for_each = local.fly_service_configs

  commit_message      = "Update ${each.value.stack} config"
  content             = shell_sensitive_script.fly_service_configs_encrypt[each.key].output["encrypted_content"]
  file                = each.key
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly
}

resource "shell_sensitive_script" "fly_service_configs_encrypt" {
  for_each = local.fly_service_configs

  environment = {
    AGE_PUBLIC_KEY = age_secret_key.fly.public_key
    CONTENT        = base64encode(each.value.content)
    CONTENT_TYPE   = "yaml"
  }

  lifecycle_commands {
    create = local.sops_encrypt_script
    delete = "true"
    read   = local.sops_encrypt_script
    update = local.sops_encrypt_script
  }

  triggers = {
    age_public_key_hash = sha256(age_secret_key.fly.public_key)
    content_hash        = sha256(each.value.content)
    script_hash         = sha256(local.sops_encrypt_script)
  }
}

resource "github_repository_file" "fly_sops_config" {
  commit_message      = "Update SOPS configuration"
  content = "creation_rules:\n  - age: ${age_secret_key.fly.public_key}\n"
  file    = ".sops.yaml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly
}

resource "github_repository_file" "fly_toml" {
  for_each = local.fly_services

  commit_message      = "Update ${each.key} Fly configuration"
  content             = shell_sensitive_script.fly_toml_encrypt[each.key].output["encrypted_content"]
  file                = "${each.key}/fly.toml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly
}

resource "shell_sensitive_script" "fly_toml_encrypt" {
  for_each = local.fly_services

  environment = {
    AGE_PUBLIC_KEY = age_secret_key.fly.public_key
    CONTENT        = base64encode(local.fly_toml_content[each.key])
    CONTENT_TYPE   = "toml"
  }

  lifecycle_commands {
    create = local.sops_encrypt_script
    delete = "true"
    read   = local.sops_encrypt_script
    update = local.sops_encrypt_script
  }

  triggers = {
    age_public_key_hash = sha256(age_secret_key.fly.public_key)
    content_hash        = sha256(local.fly_toml_content[each.key])
    script_hash         = sha256(local.sops_encrypt_script)
  }
}
