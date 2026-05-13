locals {
  # TrueNAS deploy artifacts are grouped by target server because each server has
  # its own self-hosted runner and age key.
  truenas_input_servers = {
    for server_key, server in local.servers_model : server_key => server
    if server.platform == "truenas"
  }

  # Expanded services targeting a TrueNAS server.
  truenas_input_services = {
    for service_key, service in local.services_model : service_key => service
    if service.deploy && contains(keys(local.truenas_input_servers), service.target)
  }

  # Catalog app templates live beside each service with app-specific chart values.
  truenas_prepare_catalog_templates = {
    for service_key, service in local.truenas_input_services : service_key => {
      path = "${path.module}/templates/services/${service.identity.service}/app.json.tftpl"
    }
    if fileexists("${path.module}/templates/services/${service.identity.service}/app.json.tftpl")
  }

  # Array env values are joined with '+' because the TrueNAS catalog runner
  # expects a single string per env var, not a list.
  truenas_prepare_env = {
    for service_key, service in local.truenas_input_services : service_key => {
      for env_key, env_value in {
        for input_key, input_value in service.truenas.env : input_key => (
          can(tostring(input_value))
          ? templatestring(
            tostring(input_value),
            local.services_render_context[service_key],
          )
          : join(
            "+",
            [
              for env_item in input_value : templatestring(
                tostring(env_item),
                local.services_render_context[service_key],
              )
            ],
          )
        )
        if input_value != null
      } :
      env_key => env_value
      if env_value != ""
    }
  }

  # Extends services_render_context with truenas_values and a patched
  # service.truenas.env so templates can reference rendered env vars
  # alongside chart values in one context object.
  truenas_prepare_render_context = {
    for service_key, context in local.services_render_context : service_key => merge(
      context,
      {
        truenas_values = local.truenas_prepare_values[service_key]

        service = merge(
          context.service,
          {
            truenas = merge(
              context.service.truenas,
              {
                env = local.truenas_prepare_env[service_key]
              },
            )
          },
        )
      },
    )
    if contains(keys(local.truenas_input_services), service_key)
  }

  # Pre-computes `{target}/{service.name}/{rel_path}` so truenas_render_files
  # can use the path in both the map key and the file attribute without
  # repeating the service identity lookup.
  truenas_prepare_sidecar_paths = {
    for file_key, file_config in local.services_render_files_sidecars : file_key =>
    "${file_config.target}/${local.services_model[file_config.stack].identity.name}/${file_config.rel_path}"
  }

  # Pre-computed truenas_values template variable: optional per-app env block
  # (keyed by catalog_app name, catalog services only) merged with Traefik
  # routing labels in the shape the TrueNAS deploy runner expects.
  truenas_prepare_values = {
    for service_key, context in local.services_render_context : service_key => merge(
      length(local.truenas_prepare_env[service_key]) > 0 ? {
        (coalesce(context.service.truenas.catalog_app, context.service.identity.service)) = {
          additional_envs = [
            for env_key in sort(keys(local.truenas_prepare_env[service_key])) : {
              name  = env_key
              value = local.truenas_prepare_env[service_key][env_key]
            }
          ]
        }
      } : {},
      {
        labels = [
          for label_key in sort(keys(context.service.routing_labels)) : {
            containers = [context.service.routing.container]
            key        = label_key
            value      = context.service.routing_labels[label_key]
          }
        ]
      },
    )
    if contains(keys(local.truenas_input_services), service_key)
  }

  # Encrypted GitHub files consumed by the TrueNAS deploy workflow. Compose wins
  # over catalog: a service with docker-compose.yaml.tftpl deploys as a custom
  # stack; otherwise the catalog app.json.tftpl is used. Sidecars are always included.
  truenas_render_files = merge(
    {
      # 1) Custom Docker Compose apps
      for service_key, service in local.truenas_input_services : "${service.target}/${service.identity.name}/compose.json" => {
        age_public_key = age_secret_key.server[service.target].public_key
        commit_message = "Update ${service_key} compose"
        content_type   = "json"
        file           = "${service.target}/${service.identity.name}/compose.json"

        content_base64 = sensitive(
          base64encode(
            templatefile(
              "${path.module}/templates/truenas/compose.json.tftpl",
              merge(
                local.truenas_prepare_render_context[service_key],
                {
                  compose = local.services_render_files_compose[service_key]
                },
              ),
            ),
          ),
        )
      }
      if contains(keys(local.services_render_files_compose), service_key)
    },
    {
      # 2) TrueNAS catalog apps — only when no custom compose file exists
      for service_key, service in local.truenas_input_services : "${service.target}/${service.identity.name}/app.json" => {
        age_public_key = age_secret_key.server[service.target].public_key
        commit_message = "Update ${service_key} catalog app"
        content_type   = "json"
        file           = "${service.target}/${service.identity.name}/app.json"

        content_base64 = sensitive(
          base64encode(
            jsonencode(
              provider::deepmerge::mergo(
                jsondecode(
                  templatefile(
                    "${path.module}/templates/truenas/app.json.tftpl",
                    local.truenas_prepare_render_context[service_key],
                  ),
                ),
                jsondecode(
                  templatefile(
                    local.truenas_prepare_catalog_templates[service_key].path,
                    local.truenas_prepare_render_context[service_key],
                  ),
                ),
              ),
            ),
          ),
        )
      }
      if(
        !contains(keys(local.services_render_files_compose), service_key) &&
        contains(keys(local.truenas_prepare_catalog_templates), service_key)
      )
    },
    {
      # 3) Generic sidecar files (env, configs, etc.)
      for file_key, file_config in local.services_render_files_sidecars : local.truenas_prepare_sidecar_paths[file_key] => merge(
        file_config,
        {
          age_public_key = age_secret_key.server[file_config.target].public_key
          commit_message = "Update ${file_config.stack} ${file_config.rel_path}"
          file           = local.truenas_prepare_sidecar_paths[file_key]
        },
      )
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

resource "github_repository_file" "truenas_deploy_request" {
  commit_message      = "Request changed deployments"
  file                = ".github/deploy-request.json"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas

  content = jsonencode({
    deployments = {
      for service_key, service in local.truenas_input_services : "${service.target}/${service.identity.name}" => sha256(jsonencode({
        files = {
          for file_key, file_config in local.truenas_render_files : file_config.file => nonsensitive(sha256(file_config.content_base64))
          if startswith(local.truenas_render_files[file_key].file, "${service.target}/${service.identity.name}/")
        }

        sops = sha256(yamlencode({
          creation_rules = [
            for server_key, server in local.truenas_input_servers : {
              age        = age_secret_key.server[server_key].public_key
              path_regex = "^${server_key}/"
            }
          ]
        }))

        workflow_files = local.github_workflow_file_hashes.truenas
      }))
    }
  })

  depends_on = [
    github_repository_file.truenas_sops_config,
    github_repository_file.workflow_file,
    module.encrypted_github_file_truenas,
  ]
}

module "encrypted_github_file_truenas" {
  for_each = local.truenas_render_files
  source   = "./modules/github_file_encrypted"

  age_public_key = each.value.age_public_key
  commit_message = each.value.commit_message
  content_base64 = each.value.content_base64
  content_type   = each.value.content_type
  debug_path     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.truenas}/${each.key}" : ""
  file           = each.value.file
  repository     = local.defaults.github.repositories.truenas
}

resource "github_repository_file" "truenas_sops_config" {
  commit_message      = "Update SOPS configuration"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.truenas

  content = yamlencode({
    creation_rules = [
      for server_key, server in local.truenas_input_servers : {
        age        = age_secret_key.server[server_key].public_key
        path_regex = "^${server_key}/"
      }
    ]
  })
}
