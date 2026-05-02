locals {
  # TrueNAS deploy artifacts are grouped by target server because each server has
  # its own self-hosted runner and age key.
  truenas_input_servers = {
    for server_key, server in local.servers_model_desired : server_key => server
    if server.platform == "truenas"
  }

  # Expanded services targeting a TrueNAS server.
  truenas_input_services = {
    for service_key, service in local.services_model_desired : service_key => service
    if contains(keys(local.truenas_input_servers), service.target)
  }

  # Catalog app templates live beside each service with app-specific chart values.
  truenas_prepare_catalog_templates = {
    for service_key, service in local.truenas_input_services : service_key => {
      path = "${path.module}/services/${service.identity.service}/app.json.tftpl"
    }
    if fileexists("${path.module}/services/${service.identity.service}/app.json.tftpl")
  }

  # Encrypted GitHub files consumed by the TrueNAS deploy workflow.
  truenas_render_files = merge(
    {
      for service_key, service in local.truenas_input_services : (
        "${service.target}/${service.identity.name}/compose.json"
        ) => {
        age_public_key = age_secret_key.server[service.target].public_key
        commit_message = "Update ${service_key} compose"
        content_type   = "json"
        file           = "${service.target}/${service.identity.name}/compose.json"

        content_base64 = sensitive(base64encode(templatefile(
          "${path.module}/templates/truenas/compose.json.tftpl",
          merge(local.services_render_context_vars[service_key], {
            compose = local.services_render_files_compose[service_key]
          })
        )))
      }
      if contains(keys(local.services_render_files_compose), service_key)
    },
    {
      for service_key, service in local.truenas_input_services : (
        "${service.target}/${service.identity.name}/app.json"
        ) => {
        age_public_key = age_secret_key.server[service.target].public_key
        commit_message = "Update ${service_key} catalog app"
        content_type   = "json"
        file           = "${service.target}/${service.identity.name}/app.json"

        content_base64 = sensitive(base64encode(jsonencode(provider::deepmerge::mergo(
          yamldecode(templatefile(
            "${path.module}/templates/truenas/app.json.tftpl",
            local.services_render_context_vars[service_key]
          )),
          yamldecode(templatefile(
            local.truenas_prepare_catalog_templates[service_key].path,
            local.services_render_context_vars[service_key]
          ))
        ))))
      }
      if(
        !contains(keys(local.services_render_files_compose), service_key) &&
        contains(keys(local.truenas_prepare_catalog_templates), service_key)
      )
    },
    {
      for file_key, file_config in local.services_render_files_sidecars : (
        "${file_config.target}/${local.services_model_desired[file_config.stack].identity.name}/${file_config.rel_path}"
        ) => merge(file_config, {
          age_public_key = age_secret_key.server[file_config.target].public_key
          commit_message = "Update ${file_config.stack} ${file_config.rel_path}"
          file = (
            "${file_config.target}/${local.services_model_desired[file_config.stack].identity.name}/${file_config.rel_path}"
          )
      })
      if contains(keys(local.truenas_input_servers), file_config.target)
    }
  )

}

# GitHub secret names cannot contain hyphens, so the workflow matrix computes
# the same uppercase underscore form from the server key.
resource "github_actions_secret" "truenas_age_key" {
  for_each = local.truenas_input_servers

  plaintext_value = age_secret_key.server[each.key].secret_key
  repository      = local.defaults.github.repositories.truenas
  secret_name     = "AGE_KEY_${upper(replace(each.key, "-", "_"))}"
}

resource "github_repository_file" "truenas_services_files" {
  for_each = local.truenas_render_files

  commit_message      = each.value.commit_message
  content             = shell_sensitive_script.truenas_services_files_encrypt[each.key].output["encrypted_content"]
  file                = each.value.file
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
    [for server_key, server in local.truenas_input_servers : (
      "  - path_regex: '^${server_key}/'\n    age: ${age_secret_key.server[server_key].public_key}"
    )]
  ))
}

resource "github_repository_file" "truenas_workflow_deploy" {
  commit_message      = "Update deploy workflow"
  content             = file("${path.module}/templates/workflows/truenas-deploy.yml")
  file                = ".github/workflows/deploy.yml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas
}

resource "shell_sensitive_script" "truenas_services_files_encrypt" {
  for_each = local.truenas_render_files

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
      ? "${var.debug_dir}/${local.defaults.github.repositories.truenas}/${each.key}"
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

resource "terraform_data" "truenas_validation" {
  input = keys(local.truenas_input_services)

  lifecycle {
    # A TrueNAS service is either a custom app from docker-compose.yaml.tftpl
    # or a catalog app with app-specific values.
    precondition {
      condition = length([
        for service_key, service in local.truenas_input_services : service_key
        if !contains(keys(local.services_render_files_compose), service_key) &&
        !contains(keys(local.truenas_prepare_catalog_templates), service_key)
      ]) == 0
      error_message = "TrueNAS catalog services require services/{identity.service}/app.json.tftpl: ${join(", ", [
        for service_key, service in local.truenas_input_services : service_key
        if !contains(keys(local.services_render_files_compose), service_key) &&
        !contains(keys(local.truenas_prepare_catalog_templates), service_key)
      ])}"
    }
  }
}
