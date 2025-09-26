locals {
  komodo_servers = {
    for k, v in local.homelab : k => v
    if local.homelab_resources[k].docker
  }

  komodo_stacks = merge([
    for service_key, service in local.services : {
      for target in local.services_deployments[service_key] : "${service_key}-${target}" => {
        service_key = service_key
        service     = service
        target      = target
      }
      if local.homelab_resources[target].docker
    } if service.platform == "docker" &&
    try(service.input.service, null) != null &&
    fileexists("${path.module}/docker/${service.input.service}/docker-compose.yaml")
  ]...)

  komodo_stacks_encrypt_script = <<-EOT
    set -euo pipefail

    previous_data=""
    if [ ! -t 0 ]; then
      previous_data="$(cat || true)"
    fi

    previous_hash="$(printf '%s' "$previous_data" | jq -r '.hash // ""' 2>/dev/null || true)"

    plaintext="$(printf '%s' "$CONTENT" | base64 -d)"

    if command -v sha256sum >/dev/null 2>&1; then
      hash="$(printf '%s' "$plaintext" | sha256sum | awk '{print $1}')"
    else
      hash="$(printf '%s' "$plaintext" | shasum -a 256 | awk '{print $1}')"
    fi

    if [ -n "$previous_data" ] && [ "$previous_hash" = "$hash" ]; then
      printf '%s' "$previous_data"
      exit 0
    fi

    encrypted_content="$(printf '%s' "$plaintext" | sops encrypt --age "$AGE_PUBLIC_KEY" --input-type yaml --output-type yaml /dev/stdin)"
    jq -n --arg content "$encrypted_content" --arg hash "$hash" '{content: $content, hash: $hash}'
  EOT

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

resource "shell_sensitive_script" "komodo_service_compose_encrypt" {
  for_each = local.komodo_stacks

  environment = {
    AGE_PUBLIC_KEY = local.homelab[each.value.target].output.age_public_key
    CONTENT        = base64encode(local.komodo_stacks_templates[each.key])
  }

  lifecycle_commands {
    create = local.komodo_stacks_encrypt_script
    delete = "true"
    read   = local.komodo_stacks_encrypt_script
    update = local.komodo_stacks_encrypt_script
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

  content = join("\n", [
    for k, v in local.komodo_servers : <<-EOT
      [[server]]
      description = "${v.input.description} (${upper(v.region)})"
      name = "${k}"
      tags = [${join(", ", [for tag in compact(local.homelab_tags[k]) : "\"${tag}\""])}]
      [server.config]
      address = "${v.output.fqdn_internal}:8120"
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
      description = "${stack.service.input.description} (${stack.target})"
      name = "${stack_id}"
      tags = [${join(", ", [for tag in local.services_tags[stack.service_key] : "\"${tag}\""])}]
      [stack.config]
      auto_update = true
      repo = "${data.github_user.default.login}/${var.komodo_repository}"
      run_directory = "${stack_id}"
      server = "${stack.target}"
      [stack.config.pre_deploy]
      command = "sops decrypt -i compose.yaml"
    EOT
  ])
}

resource "github_repository_file" "komodo_stacks_docker_compose" {
  for_each = local.komodo_stacks

  commit_message      = "Update ${each.key} SOPS-encrypted compose"
  content             = shell_sensitive_script.komodo_service_compose_encrypt[each.key].output["content"]
  file                = "${each.key}/compose.yaml"
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
