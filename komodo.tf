locals {
  komodo_stacks = merge([
    for service_key, service in local.services : {
      for target in service.deployments : "${service.name}-${local.servers[target].slug}" => {
        service     = service
        service_key = service_key
        server      = local.servers[target]
        server_key  = target
      }
      if local.servers_resources[target].docker
    } if service.input.service != null && service.platform == "docker" && fileexists("${path.module}/docker/${service.input.service}/docker-compose.yaml")
  ]...)

  komodo_stacks_templates = {
    for k, v in local.komodo_stacks : k => templatefile(
      "${path.module}/docker/${v.service.input.service}/docker-compose.yaml",
      {
        defaults = var.defaults
        server   = v.server
        service  = v.service
      }
    )
  }
}

resource "github_repository_file" "komodo_resource_sync" {
  commit_message      = "Update Komodo ResourceSync configuration"
  file                = "resource_sync.toml"
  overwrite_on_create = true
  repository          = var.komodo_repository

  content = <<-EOT
    [[resource_sync]]
    name = "komodo"

    [resource_sync.config]
    delete = true
    git_account = "${data.github_user.default.login}"
    managed = true
    repo = "${data.github_user.default.login}/${var.komodo_repository}"
    resource_path = ["."]
  EOT
}

resource "github_repository_file" "komodo_servers" {
  commit_message      = "Update Komodo server configurations"
  file                = "servers.toml"
  overwrite_on_create = true
  repository          = var.komodo_repository

  content = join("\n", [
    for k, v in local.servers : <<-EOT
      [[server]]
      description = "${v.input.description != null ? v.input.description : k} (${upper(v.region)})"
      name = "${v.slug}"
      tags = [${join(", ", [for tag in v.tags : "\"${tag}\""])}]
      [server.config]
      address = "https://${v.output.fqdn_internal}:8120"
      enabled = true
      region = "${v.region}"
    EOT
    if v.resources.docker
  ])
}

resource "github_repository_file" "komodo_stacks" {
  commit_message      = "Update Komodo stack configurations"
  file                = "stacks.toml"
  overwrite_on_create = true
  repository          = var.komodo_repository

  content = join("\n", [
    for k, v in local.komodo_stacks : <<-EOT
      [[stack]]
      description = "${v.service.input.description != null ? v.service.input.description : v.service.name} (${v.server.slug})"
      name = "${k}"
      tags = [${join(", ", [for tag in v.service.tags : "\"${tag}\""])}]
      [stack.config]
      auto_update = true
      repo = "${data.github_user.default.login}/${var.komodo_repository}"
      run_directory = "${k}"
      server = "${v.server.slug}"
      [stack.config.pre_deploy]
      command = "SOPS_AGE_KEY=[[AGE_SECRET_KEY]] sops decrypt -i compose.yaml"
    EOT
  ])
}

resource "github_repository_file" "komodo_stacks_compose" {
  for_each = local.komodo_stacks

  commit_message      = "Update ${each.key} SOPS-encrypted compose"
  content             = shell_sensitive_script.komodo_service_compose_encrypt[each.key].output["encrypted_content"]
  file                = "${each.key}/compose.yaml"
  overwrite_on_create = true
  repository          = var.komodo_repository
}

resource "shell_sensitive_script" "komodo_service_compose_encrypt" {
  for_each = local.komodo_stacks

  environment = {
    AGE_PUBLIC_KEY = each.value.server.output.age_public_key
    CONTENT        = base64encode(local.komodo_stacks_templates[each.key])
  }

  lifecycle_commands {
    create = "${path.module}/scripts/komodo-encrypt.sh"
    delete = "true"
    read   = "${path.module}/scripts/komodo-encrypt.sh"
    update = "${path.module}/scripts/komodo-encrypt.sh"
  }

  triggers = {
    age_public_key_hash = sha256(each.value.server.output.age_public_key)
    content_hash        = sha256(local.komodo_stacks_templates[each.key])
    script_hash         = filemd5("${path.module}/scripts/komodo-encrypt.sh")
  }
}
