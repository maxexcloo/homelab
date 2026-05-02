locals {
  # Expanded services whose deployment target is Fly.io.
  fly_input_services = {
    for service_key, service in local.services_model_desired : service_key => service
    if service.target == "fly"
  }

  # GitHub files written to the Fly deployment repository. File keys include
  # the service directory so multiple Fly services can share one repo.
  fly_render_files = merge(
    {
      for service_key, service in local.fly_input_services : (
        "${service.platform_config.fly.app_name}/fly.toml"
        ) => {
        age_public_key = age_secret_key.fly.public_key
        commit_message = "Update ${service.platform_config.fly.app_name} configuration"
        content_type   = "binary"
        file           = "${service.platform_config.fly.app_name}/fly.toml"

        content_base64 = sensitive(base64encode(templatefile(
          "${path.module}/templates/fly/fly.toml.tftpl",
          local.services_render_context_vars[service_key]
        )))
      }
    },
    {
      for service_key, service in local.fly_input_services : (
        "${service.platform_config.fly.app_name}/.certs"
        ) => {
        age_public_key = age_secret_key.fly.public_key
        commit_message = "Update ${service.platform_config.fly.app_name} certificate hostnames"
        content_type   = "binary"
        file           = "${service.platform_config.fly.app_name}/.certs"

        content_base64 = base64encode(templatefile(
          "${path.module}/templates/fly/certs.tftpl",
          local.services_render_context_vars[service_key]
        ))
      }
      if length(service.networking.urls) > 0
    },
    {
      for service_key, service in local.fly_input_services : (
        "${service.platform_config.fly.app_name}/.machine-count"
        ) => {
        age_public_key = age_secret_key.fly.public_key
        commit_message = "Update ${service.platform_config.fly.app_name} machine count"
        content_base64 = base64encode("${service.platform_config.fly.machine_count}\n")
        content_type   = "binary"
        file           = "${service.platform_config.fly.app_name}/.machine-count"
      }
      if service.platform_config.fly.machine_count != null
    },
    {
      for file_key, file_config in local.services_render_files_sidecars : (
        "${local.fly_input_services[file_config.stack].platform_config.fly.app_name}/${file_config.rel_path}"
        ) => merge(file_config, {
          age_public_key = age_secret_key.fly.public_key
          commit_message = "Update ${file_config.stack} ${file_config.rel_path}"
          file           = "${local.fly_input_services[file_config.stack].platform_config.fly.app_name}/${file_config.rel_path}"
      })
      if file_config.target == "fly"
    }
  )
}

# Shared age key for the Fly deployment repository; per-service files are
# separated by directory rather than by recipient key.
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
    FILENAME       = each.value.file
    SOPS_CONFIG    = "/dev/null"

    DEBUG_PATH = (
      var.debug_dir != ""
      ? "${var.debug_dir}/${local.defaults.github.repositories.fly}/${each.key}"
      : ""
    )
  }

  lifecycle_commands {
    create = sensitive(local.script_encrypt_sops)
    delete = "true"
    read   = sensitive(local.script_encrypt_sops)
    update = sensitive(local.script_encrypt_sops)
  }

  triggers = {
    age_public_key_hash = sha256(each.value.age_public_key)
    script_hash         = sha256(local.script_encrypt_sops)
  }
}
