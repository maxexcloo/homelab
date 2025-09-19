locals {
  komodo_servers = {
    for k, v in local.homelab : k => v
    if contains(local.homelab_tags[k], "komodo")
  }

  komodo_stacks = merge([
    for service_key, service in local.services : (
      service.platform == "docker" &&
      try(service.input.service, null) != null &&
      fileexists("${path.module}/docker/${service.input.service}/docker-compose.yaml")
      ) ? {
      for target in local.services_deployments[service_key] : "${service_key}-${target}" => {
        service_key = service_key
        service     = service
        target      = target
      }
    } : {}
  ]...)

  komodo_stacks_templates = {
    for stack_id, stack in local.komodo_stacks : stack_id => templatefile(
      "${path.module}/docker/${stack.service.input.service}/docker-compose.yaml",
      {
        server  = local.homelab[stack.target]
        service = stack.service
        target  = stack.target
      }
    )
  }
}

# Encrypt docker-compose files using shell provider with SOPS (no temp files)
resource "shell_sensitive_script" "komodo_service_compose_encrypt" {
  for_each = local.komodo_stacks

  environment = {
    AGE_PUBLIC_KEY = local.homelab[each.value.target].output.age_public_key
    CONTENT        = base64encode(local.komodo_stacks_templates[each.key])
  }

  lifecycle_commands {
    create = <<-EOT
      set -eu
      content="$(printf '%s' "$CONTENT" | base64 -d | sops encrypt --age "$AGE_PUBLIC_KEY" --input-type yaml --output-type yaml /dev/stdin)"
      jq --null-input --arg content "$content" '{"content": $content}'
    EOT
    delete = "true"
    read   = <<-EOT
      set -eu
      content="$(printf '%s' "$CONTENT" | base64 -d | sops encrypt --age "$AGE_PUBLIC_KEY" --input-type yaml --output-type yaml /dev/stdin)"
      jq --null-input --arg content "$content" '{"content": $content}'
    EOT
    update = <<-EOT
      set -eu
      content="$(printf '%s' "$CONTENT" | base64 -d | sops encrypt --age "$AGE_PUBLIC_KEY" --input-type yaml --output-type yaml /dev/stdin)"
      jq --null-input --arg content "$content" '{"content": $content}'
    EOT

  }

  triggers = {
    age_public_key_hash = sha256(local.homelab[each.value.target].output.age_public_key)
    content_hash        = sha256(local.komodo_stacks_templates[each.key])
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
    include_variables = true
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

  content = join("\n\n", [
    for k, v in local.komodo_servers : <<-EOT
      [[server]]
      description = "${v.input.description}"
      name = "${k}"
      tags = [${join(", ", [for tag in compact(local.homelab_tags[k]) : "\"${tag}\""])}]

      [server.config]
      address = "http://${v.output.fqdn_internal}:8120"
      enabled = true
      region = "${v.region}"
    EOT
  ])
}

resource "github_repository_file" "komodo_stacks" {
  commit_message      = "Update Komodo stack configurations"
  file                = "stacks.toml"
  overwrite_on_create = true
  repository          = var.komodo_repository

  content = join("\n\n", [
    for stack_id, stack in local.komodo_stacks : <<-EOT
      [[stack]]
      description = "${stack.service.input.description}"
      name = "${stack_id}"
      tags = [${join(", ", [for tag in compact(concat(try(local.services_tags[stack.service_key], []), [stack.service.platform])) : "\"${tag}\""])}]

      [stack.config]
      auto_update = true
      repo = "${data.github_user.default.login}/${var.komodo_repository}"
      run_directory = "${stack_id}"
      server = "${stack.target}"

      [stack.config.pre_deploy]
      command = "sops decrypt -i docker-compose.yaml"
    EOT
  ])
}

resource "github_repository_file" "komodo_stacks_docker_compose" {
  for_each = local.komodo_stacks

  commit_message      = "Update ${each.key} SOPS-encrypted docker-compose"
  content             = shell_sensitive_script.komodo_service_compose_encrypt[each.key].output["content"]
  file                = "${each.key}/docker-compose.yaml"
  overwrite_on_create = true
  repository          = var.komodo_repository
}

resource "github_repository_file" "komodo_variables" {
  commit_message      = "Update Komodo variable configurations"
  file                = "variables.toml"
  overwrite_on_create = true
  repository          = var.komodo_repository

  content = <<-EOT
    [[variable]]
    name = "DEFAULT_EMAIL"
    value = "${var.default_email}"

    [[variable]]
    name = "DEFAULT_ORGANIZATION" 
    value = "${var.default_organization}"

    [[variable]]
    name = "DEFAULT_TIMEZONE"
    value = "${var.default_timezone}"

    [[variable]]
    name = "DOMAIN_EXTERNAL"
    value = "${var.domain_external}"

    [[variable]]
    name = "DOMAIN_INTERNAL"
    value = "${var.domain_internal}"
  EOT
}
