locals {
  komodo_servers = {
    for k, v in local.servers : k => v
    if local.servers_resources[k].docker
  }

  komodo_stacks = merge([
    for service_key, service in local.services : {
      for target in local.services_deployments[service_key] : "${service.name}-${target}" => {
        service_key = service_key
        service     = service
        target      = target
      }
      if local.servers_resources[target].docker
    } if service.platform == "docker" && service.input.service.value != null && fileexists("${path.module}/docker/${service.input.service.value}/docker-compose.yaml")
  ]...)

  komodo_stacks_encrypt_script = <<-EOT
    set -euo pipefail

    PREVIOUS_DATA=""
    if [ ! -t 0 ]; then
      PREVIOUS_DATA="$(cat || true)"
    fi

    PREVIOUS_HASH="$(printf '%s' "$PREVIOUS_DATA" | jq -r '.hash // ""' 2>/dev/null || true)"
    PLAINTEXT="$(printf '%s' "$CONTENT" | base64 -d)"
    HASH="$(printf '%s' "$PLAINTEXT" | sha256sum | awk '{print $1}')"

    if [ -n "$PREVIOUS_DATA" ] && [ "$PREVIOUS_HASH" = "$HASH" ]; then
      printf '%s' "$PREVIOUS_DATA"
      exit 0
    fi

    ENCRYPTED_CONTENT="$(printf '%s' "$PLAINTEXT" | sops encrypt --age "$AGE_PUBLIC_KEY" --input-type yaml --output-type yaml /dev/stdin)"
    jq -n --arg encrypted_content "$ENCRYPTED_CONTENT" --arg hash "$HASH" '{encrypted_content: $encrypted_content, hash: $hash}'
  EOT

  komodo_stacks_templates = {
    for stack_id, stack in local.komodo_stacks : stack_id => templatefile(
      "${path.module}/docker/${stack.service.input.service.value}/docker-compose.yaml",
      {
        defaults = var.defaults
        server   = local.servers[stack.target]
        service  = stack.service
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
    for k, v in local.komodo_servers : <<-EOT
      [[server]]
      description = "${v.input.description.value != null ? v.input.description.value : k} (${upper(v.region)})"
      name = "${k}"
      tags = [${join(", ", [for tag in v.tags : "\"${tag}\""])}]
      [server.config]
      address = "https://${local.servers_resources[k].komodo ? "periphery" : v.output.fqdn_internal}:8120"
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

  content = join("\n", [
    for stack_id, stack in local.komodo_stacks : <<-EOT
      [[stack]]
      description = "${stack.service.input.description.value != null ? stack.service.input.description.value : stack.service_key} (${stack.target})"
      name = "${stack_id}"
      tags = [${join(", ", [for tag in stack.service.tags : "\"${tag}\""])}]
      [stack.config]
      auto_update = true
      repo = "${data.github_user.default.login}/${var.komodo_repository}"
      run_directory = "${stack_id}"
      server = "${stack.target}"
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
    AGE_PUBLIC_KEY = local.servers[each.value.target].output.age_public_key
    CONTENT        = base64encode(local.komodo_stacks_templates[each.key])
  }

  lifecycle_commands {
    create = local.komodo_stacks_encrypt_script
    delete = "true"
    read   = local.komodo_stacks_encrypt_script
    update = local.komodo_stacks_encrypt_script
  }

  triggers = {
    age_public_key_hash = sha256(local.servers[each.value.target].output.age_public_key)
    content_hash        = sha256(local.komodo_stacks_templates[each.key])
  }
}
