locals {
  # TrueNAS deploy artifacts are grouped by target server because each server has
  # its own self-hosted runner and age key.
  truenas_input_servers = {
    for k, v in local.servers_model_desired : k => v
    if v.platform == "truenas"
  }

  # Expanded services targeting a TrueNAS server.
  truenas_input_services = {
    for k, v in local.services_model_desired : k => v
    if contains(keys(local.truenas_input_servers), v.target)
  }

  # Catalog services are the TrueNAS services that do not provide Compose files.
  truenas_prepare_catalog_services = {
    for k, v in local.truenas_input_services : k => v
    if !contains(keys(local.services_rendered_compose), k) && contains(keys(local.truenas_prepare_catalog_templates), k)
  }

  # Catalog app templates live beside each service with app-specific chart values.
  truenas_prepare_catalog_templates = {
    for k, v in local.truenas_input_services : k => {
      path = "${path.module}/services/${v.identity.name}/app.json.tftpl"
    }
    if fileexists("${path.module}/services/${v.identity.name}/app.json.tftpl")
  }

  # Encrypted GitHub files consumed by the TrueNAS deploy workflow.
  truenas_render_files = merge(
    {
      for k, v in local.truenas_input_services : "${v.target}/${v.identity.name}/compose.json" => {
        age_public_key = age_secret_key.server[v.target].public_key
        commit_message = "Update ${k} compose"
        content_type   = "json"
        file           = "${v.target}/${v.identity.name}/compose.json"

        content_base64 = sensitive(base64encode(templatefile(
          "${path.module}/templates/truenas/compose.json.tftpl",
          merge(local.services_render_vars[k], {
            compose = local.services_rendered_compose[k]
          })
        )))
      }
      if contains(keys(local.services_rendered_compose), k)
    },
    {
      for k, v in local.truenas_prepare_catalog_services : "${v.target}/${v.identity.name}/app.json" => {
        age_public_key = age_secret_key.server[v.target].public_key
        commit_message = "Update ${k} catalog app"
        content_type   = "json"
        file           = "${v.target}/${v.identity.name}/app.json"

        content_base64 = sensitive(base64encode(jsonencode(provider::deepmerge::mergo(
          yamldecode(templatefile("${path.module}/templates/truenas/app.json.tftpl", local.services_render_vars[k])),
          yamldecode(templatefile(local.truenas_prepare_catalog_templates[k].path, local.services_render_vars[k]))
        ))))
      }
    },
    {
      for k, v in local.services_rendered_files : "${v.target}/${local.services_model_desired[v.stack].identity.name}/${v.rel_path}" => merge(v, {
        age_public_key = age_secret_key.server[v.target].public_key
        commit_message = "Update ${v.stack} ${v.rel_path}"
        file           = "${v.target}/${local.services_model_desired[v.stack].identity.name}/${v.rel_path}"
      })
      if contains(keys(local.truenas_input_servers), v.target)
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
    [for k, v in local.truenas_input_servers : "  - path_regex: '^${k}/'\n    age: ${age_secret_key.server[k].public_key}"]
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
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.truenas}/${each.key}" : ""
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

resource "terraform_data" "truenas_validation" {
  input = keys(local.truenas_input_services)

  lifecycle {
    # A TrueNAS service is either a custom app from docker-compose.yaml.tftpl
    # or a catalog app with app-specific values.
    precondition {
      condition = length([
        for k, v in local.truenas_input_services : k
        if !contains(keys(local.services_rendered_compose), k) &&
        !contains(keys(local.truenas_prepare_catalog_templates), k)
      ]) == 0
      error_message = "TrueNAS catalog services require services/{identity.name}/app.json.tftpl: ${join(", ", [
        for k, v in local.truenas_input_services : k
        if !contains(keys(local.services_rendered_compose), k) &&
        !contains(keys(local.truenas_prepare_catalog_templates), k)
      ])}"
    }
  }
}
