locals {
  # Expanded services whose deployment target is Fly.io.
  fly_input_services = {
    for k, v in local.services_model_desired : k => v
    if v.target == "fly"
  }

  # GitHub files written to the Fly deployment repository. File keys include
  # the app directory so multiple Fly apps can share one repo.
  fly_render_files = merge(
    {
      for k, v in local.fly_input_services : "${v.platform_config.fly.app_name}/fly.toml" => {
        age_public_key = age_secret_key.fly.public_key
        commit_message = "Update ${v.platform_config.fly.app_name} Fly configuration"
        content_base64 = sensitive(base64encode(templatefile("${path.module}/templates/fly/fly.toml.tftpl", local.services_render_vars[k])))
        content_type   = "binary"
        file           = "${v.platform_config.fly.app_name}/fly.toml"
      }
    },
    {
      for k, v in local.fly_input_services : "${v.platform_config.fly.app_name}/.certs" => {
        age_public_key = age_secret_key.fly.public_key
        commit_message = "Update ${v.platform_config.fly.app_name} certificate hostnames"
        content_base64 = base64encode(templatefile("${path.module}/templates/fly/certs.tftpl", local.services_render_vars[k]))
        content_type   = "binary"
        file           = "${v.platform_config.fly.app_name}/.certs"
      }
      if length(v.networking.urls) > 0
    },
    {
      for k, v in local.services_rendered_files : "${local.fly_input_services[v.stack].platform_config.fly.app_name}/${v.rel_path}" => merge(v, {
        age_public_key = age_secret_key.fly.public_key
        commit_message = "Update ${v.stack} ${v.rel_path}"
        file           = "${local.fly_input_services[v.stack].platform_config.fly.app_name}/${v.rel_path}"
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

resource "github_repository_file" "fly_services_files" {
  for_each = local.fly_render_files

  commit_message      = each.value.commit_message
  content             = shell_sensitive_script.fly_services_files_encrypt[each.key].output["encrypted_content"]
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

resource "shell_sensitive_script" "fly_services_files_encrypt" {
  for_each = local.fly_render_files

  # The script receives base64 content and returns encrypted text for GitHub.
  # DEBUG_PATH intentionally writes plaintext only when explicitly configured.
  environment = {
    AGE_PUBLIC_KEY = each.value.age_public_key
    CONTENT        = sensitive(each.value.content_base64)
    CONTENT_TYPE   = each.value.content_type
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.fly}/${each.key}" : ""
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
