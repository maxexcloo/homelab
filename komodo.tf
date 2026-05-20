locals {
  # Komodo only receives services with a rendered compose file on Docker-capable
  # server targets.
  komodo_input_stacks = {
    for service_key, service in local.services_model : service_key => service
    if(
      try(local.servers_model[service.target], null) != null &&
      local.servers_model[service.target].features.docker &&
      try(local.services_render_write_compose[service_key], null) != null
    )
  }

  # Encrypted GitHub files consumed by Komodo ResourceSync. Service sidecar files
  # reuse the same relative paths as the service artifact model.
  komodo_render_files = merge(
    {
      for stack_key, stack in local.komodo_input_stacks : "${stack_key}/compose.yaml" => {
        age_public_key = age_secret_key.server[stack.target].public_key
        commit_message = "Update ${stack_key} compose"
        content_base64 = sensitive(base64encode(local.services_render_write_compose[stack_key]))
        content_type   = "yaml"
        file           = "${stack_key}/compose.yaml"
      }
    },
    {
      for file_key, file_config in local.services_render_write_sidecars : file_key => merge(
        file_config,
        {
          age_public_key = age_secret_key.server[file_config.target].public_key
          commit_message = "Update ${file_config.stack} ${file_config.rel_path}"
          file           = file_key
        },
      )
      if(
        try(local.servers_model[file_config.target], null) != null &&
        local.servers_model[file_config.target].features.docker
      )
    }
  )
}

resource "github_repository_file" "komodo_resource_sync" {
  commit_message      = "Update Komodo resource sync configuration"
  file                = "resource_sync.toml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo

  content = templatefile(
    "${path.module}/templates/komodo/resource_sync.toml.tftpl",
    {
      owner      = local.defaults.github.owner
      repository = local.defaults.github.repositories.komodo
    },
  )
}

resource "github_repository_file" "komodo_servers" {
  commit_message      = "Update Komodo server configurations"
  file                = "servers.toml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo

  content = sensitive(
    templatefile(
      "${path.module}/templates/komodo/servers.toml.tftpl",
      {
        servers = local.servers
      },
    ),
  )
}

# Per-stack SOPS rules let each target server decrypt only the stacks assigned
# to it.
resource "github_repository_file" "komodo_sops_config" {
  commit_message      = "Update SOPS configuration"
  file                = ".sops.yaml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo

  content = yamlencode({
    creation_rules = [
      for stack_key, stack in local.komodo_input_stacks : {
        age        = age_secret_key.server[stack.target].public_key
        path_regex = "^${stack_key}/"
      }
    ]
  })
}

resource "github_repository_file" "komodo_stacks" {
  commit_message      = "Update Komodo stack configurations"
  file                = "stacks.toml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.komodo

  content = templatefile(
    "${path.module}/templates/komodo/stacks.toml.tftpl",
    {
      owner      = local.defaults.github.owner
      repository = local.defaults.github.repositories.komodo
      stacks     = local.komodo_input_stacks
    },
  )
}

module "encrypted_github_file_komodo" {
  for_each = nonsensitive(local.komodo_render_files)
  source   = "./modules/github_file_encrypted"

  age_public_key = each.value.age_public_key
  commit_message = each.value.commit_message
  content_base64 = each.value.content_base64
  content_type   = each.value.content_type
  debug_path     = var.debug_dir != "" ? "${var.debug_dir}/${local.defaults.github.repositories.komodo}/${each.key}" : ""
  file           = each.value.file
  repository     = local.defaults.github.repositories.komodo
}
