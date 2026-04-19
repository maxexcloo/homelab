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

  truenas_services_catalog = {
    for k, v in local.truenas_services : k => v
    if !contains(keys(local.services_compose), k) && contains(keys(local.truenas_services_catalog_sources), k)
  }

  # Catalog app payloads live beside the service so app-specific chart details
  # do not need central Terraform wrapping logic.
  truenas_services_catalog_sources = merge(
    {
      for k, v in local.truenas_services : k => {
        path            = "${path.module}/services/${v.identity.name}/app.json"
        render_template = false
      }
      if fileexists("${path.module}/services/${v.identity.name}/app.json")
    },
    {
      for k, v in local.truenas_services : k => {
        path            = "${path.module}/services/${v.identity.name}/app.json.tftpl"
        render_template = true
      }
      if fileexists("${path.module}/services/${v.identity.name}/app.json.tftpl")
    }
  )

  truenas_services_file = merge(
    {
      for k, v in local.truenas_services : "${v.target}/${v.identity.name}/compose.json" => {
        age_public_key = local.servers[v.target].age_public_key
        commit_message = "Update ${k} compose"
        content_base64 = sensitive(base64encode(templatefile(
          "${path.module}/templates/truenas/compose.json.tftpl",
          merge(local.services_template_vars[k], {
            compose = local.services_compose[k]
          })
        )))
        content_type = "json"
        file         = "${v.target}/${v.identity.name}/compose.json"
      }
      if contains(keys(local.services_compose), k)
    },
    {
      for k, v in local.truenas_services_catalog : "${v.target}/${v.identity.name}/app.json" => {
        age_public_key = local.servers[v.target].age_public_key
        commit_message = "Update ${k} catalog app"
        content_base64 = sensitive(base64encode(
          local.truenas_services_catalog_sources[k].render_template ?
          templatefile(local.truenas_services_catalog_sources[k].path, merge(local.services_template_vars[k], {
            truenas_labels = local.truenas_services_labels[k]
          })) :
          file(local.truenas_services_catalog_sources[k].path)
        ))
        content_type = "json"
        file         = "${v.target}/${v.identity.name}/app.json"
      }
    },
    {
      for k, v in local.services_files : "${v.target}/${local.services[v.stack].identity.name}/${v.rel_path}" => merge(v, {
        age_public_key = local.servers[v.target].age_public_key
        commit_message = "Update ${v.stack} ${v.rel_path}"
        file           = "${v.target}/${local.services[v.stack].identity.name}/${v.rel_path}"
      })
      if contains(keys(local.truenas_servers), v.target)
    }
  )

  # TrueNAS catalog labels use the same Docker label source as Komodo/custom
  # apps, but TrueNAS expects a list with explicit target containers.
  truenas_services_labels = {
    for k, v in local.truenas_services_catalog : k => [
      for label_key in sort(keys(local.services_labels[k])) : {
        key   = label_key
        value = local.services_labels[k][label_key]

        containers = length(v.platform_config.truenas.containers) > 0 ? v.platform_config.truenas.containers : [v.identity.name]
      }
    ]
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

resource "github_repository_file" "truenas_services_file" {
  for_each = local.truenas_services_file

  commit_message      = each.value.commit_message
  content             = shell_sensitive_script.truenas_services_file_encrypt[each.key].output["encrypted_content"]
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

resource "shell_sensitive_script" "truenas_services_file_encrypt" {
  for_each = local.truenas_services_file

  environment = {
    AGE_PUBLIC_KEY = each.value.age_public_key
    CONTENT        = sensitive(each.value.content_base64)
    CONTENT_TYPE   = each.value.content_type
    DEBUG_PATH     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.truenas}/${each.key}" : ""
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

resource "terraform_data" "truenas_validation" {
  input = keys(local.truenas_services)

  lifecycle {
    # A TrueNAS service is either a custom app from docker-compose.yaml(.tftpl)
    # or a catalog app with app-specific values.
    precondition {
      condition = length([
        for k, v in local.truenas_services : k
        if !contains(keys(local.services_compose), k) &&
        !contains(keys(local.truenas_services_catalog_sources), k)
      ]) == 0
      error_message = "TrueNAS catalog services require services/{identity.name}/app.json or app.json.tftpl: ${join(", ", [
        for k, v in local.truenas_services : k
        if !contains(keys(local.services_compose), k) &&
        !contains(keys(local.truenas_services_catalog_sources), k)
      ])}"
    }
  }
}
