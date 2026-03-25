locals {
  komodo_script_encrypt = <<-EOT
    #!/bin/bash
    set -euo pipefail

    DATA="$(printf '%s' "$CONTENT" | base64 -d)"

    PREVIOUS_DATA=""
    if [ ! -t 0 ]; then
      PREVIOUS_DATA="$(cat || true)"
    fi

    HASH="$(printf '%s' "$DATA" | sha256sum | awk '{print $1}')"
    PREVIOUS_HASH="$(printf '%s' "$PREVIOUS_DATA" | jq -r '.hash // ""' 2>/dev/null || true)"

    if [ -n "$PREVIOUS_DATA" ] && [ "$PREVIOUS_HASH" = "$HASH" ]; then
      printf '%s' "$PREVIOUS_DATA"
      exit 0
    fi

    ENCRYPTED_CONTENT="$(printf '%s' "$DATA" | sops encrypt --age "$AGE_PUBLIC_KEY" --input-type yaml --output-type yaml /dev/stdin)"

    jq -n --arg encrypted_content "$ENCRYPTED_CONTENT" --arg hash "$HASH" '{encrypted_content: $encrypted_content, hash: $hash}'
  EOT

  komodo_stacks = {
    for k, v in local.services : k => v
    if v.identity.service != "" &&
    local.servers[v.server].features.docker &&
    fileexists("${path.module}/docker/${v.identity.service}/docker-compose.yaml")
  }

  komodo_stacks_templates = {
    for k, v in local.komodo_stacks : k => templatefile(
      "${path.module}/docker/${v.identity.service}/docker-compose.yaml",
      {
        defaults = local.defaults
        server   = local.servers[v.server]
        servers  = local.servers
        service  = v
        services = local.services
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
      name = "${k}"
      description = "${v.identity.description} (${upper(v.identity.region)})"

      [server.config]
      address = "https://${v.fqdn_internal}:8120"
      enabled = true
      region = "${v.identity.region}"
    EOT
    if v.features.docker
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
      name = "${k}"
      description = "${v.identity.description}"

      [stack.config]
      auto_update = true
      repo = "${data.github_user.default.login}/${var.komodo_repository}"
      run_directory = "${k}"
      server = "${v.server}"

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
    AGE_PUBLIC_KEY = local.servers[each.value.server].age_public_key
    CONTENT        = base64encode(local.komodo_stacks_templates[each.key])
  }

  lifecycle_commands {
    create = local.komodo_script_encrypt
    delete = "true"
    read   = local.komodo_script_encrypt
    update = local.komodo_script_encrypt
  }

  triggers = {
    age_public_key_hash = sha256(local.servers[each.value.server].age_public_key)
    content_hash        = sha256(local.komodo_stacks_templates[each.key])
    script_hash         = sha256(local.komodo_script_encrypt)
  }
}
