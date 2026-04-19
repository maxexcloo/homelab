locals {
  # Fly app names are part of the remote identity, so generated suffixes are
  # stable random resources rather than recomputed strings.
  _services_fly_computed = {
    for k, v in local._services_computed : k => {
      platform_config = merge(v.platform_config, {
        fly = merge(v.platform_config.fly, {
          app_name = trimsuffix(coalesce(v.platform_config.fly.app_name, "${v.identity.name}-${random_string.fly_service[k].result}"), ".fly.dev")
        })
      })
    }
    if v.target == "fly"
  }

  fly_services = {
    for k, v in local.services : k => v
    if v.target == "fly"
  }

  fly_services_file = merge(
    {
      for k, v in local.fly_services : "${v.platform_config.fly.app_name}/fly.toml" => {
        age_public_key = age_secret_key.fly.public_key
        commit_message = "Update ${v.platform_config.fly.app_name} Fly configuration"
        content_base64 = sensitive(base64encode(templatefile("${path.module}/templates/fly/fly.toml.tftpl", local.services_template_vars[k])))
        content_type   = "binary"
        file           = "${v.platform_config.fly.app_name}/fly.toml"
      }
    },
    {
      for k, v in local.fly_services : "${v.platform_config.fly.app_name}/.certs" => {
        age_public_key = age_secret_key.fly.public_key
        commit_message = "Update ${v.platform_config.fly.app_name} certificate hostnames"
        content_base64 = base64encode(templatefile("${path.module}/templates/fly/certs.tftpl", local.services_template_vars[k]))
        content_type   = "binary"
        file           = "${v.platform_config.fly.app_name}/.certs"
      }
      if length([for url in v.networking.urls : url if url != v.fqdn_external]) > 0
    },
    {
      for k, v in local.services_files : "${local.fly_services[v.stack].platform_config.fly.app_name}/${v.rel_path}" => merge(v, {
        age_public_key = age_secret_key.fly.public_key
        commit_message = "Update ${v.stack} ${v.rel_path}"
        file           = "${local.fly_services[v.stack].platform_config.fly.app_name}/${v.rel_path}"
      })
      if v.target == "fly"
    }
  )
}

# Shared age key for the Fly deployment repository; per-app files are separated
# by directory rather than by recipient key.
resource "github_actions_secret" "fly_age_key" {
  plaintext_value = age_secret_key.fly.secret_key
  repository      = local.defaults.github.repositories.fly
  secret_name     = "AGE_KEY"
}

resource "github_repository_file" "fly_services_file" {
  for_each = local.fly_services_file

  commit_message      = each.value.commit_message
  content             = shell_sensitive_script.fly_services_file_encrypt[each.key].output["encrypted_content"]
  file                = each.value.file
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

resource "shell_sensitive_script" "fly_services_file_encrypt" {
  for_each = local.fly_services_file

  environment = {
    AGE_PUBLIC_KEY = each.value.age_public_key
    CONTENT        = sensitive(each.value.content_base64)
    CONTENT_TYPE   = each.value.content_type
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.fly}/${each.key}" : ""
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
