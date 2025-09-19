locals {
  komodo_homelab = {
    for k, v in local.homelab : k => v
    if contains(local.homelab_tags[k], "komodo")
  }

  komodo_services = {
    for k, v in local.services : k => v
    if length(local.services_deployments[k]) > 0 && v.platform == "docker" && fileexists("${path.module}/docker/${v.service}/docker-compose.yaml")
  }

  komodo_stack_templates = {
    for k, v in local.komodo_services : k => templatefile("${path.module}/docker/${v.service}/docker-compose.yaml",
      {
        server = length(local.services_deployments[k]) > 0 ? local.homelab[local.services_deployments[k][0]] : null
        service = v
      }
    )
  }
}

# Encrypt docker-compose files using shell provider with SOPS (no temp files)
resource "shell_sensitive_script" "komodo_service_compose_encrypt" {
  for_each = nonsensitive(toset(keys(local.komodo_services)))

  environment = {
    AGE_PUBLIC_KEY = local.homelab[local.services_deployments[each.value][0]].output.age_public_key
    CONTENT        = base64encode(local.komodo_stack_templates[each.value])
  }

  lifecycle_commands {
    create = "echo '$CONTENT | base64 -d | sops encrypt --age '$AGE_PUBLIC_KEY' --input-type yaml --output-type yaml /dev/stdin"
    delete = "true"
    read   = "echo '$CONTENT | base64 -d | sops encrypt --age '$AGE_PUBLIC_KEY' --input-type yaml --output-type yaml /dev/stdin"
    update = "echo '$CONTENT | base64 -d | sops encrypt --age '$AGE_PUBLIC_KEY' --input-type yaml --output-type yaml /dev/stdin"

  }

  triggers = {
    age_public_key_hash = sha256(local.homelab[local.services_deployments[each.value][0]].output.age_public_key)
    content_hash        = sha256(local.komodo_stack_templates[each.value])
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
    for k, v in local.komodo_homelab : <<-EOT
      [[server]]
      description = "${v.input.description}"
      name = "${k}"
      tags = [${v.input.tags}]

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
    for k, v in local.komodo_services : <<-EOT
      [[stack]]
      description = "${v.input.description}"
      name = "${k}"
      tags = [${v.input.tags}]

      [stack.config]
      auto_update = true
      repo = "${data.github_user.default.login}${var.komodo_repository}"
      run_directory = "${k}"
      server = "${local.services_deployments[k][0]}"

      [stack.config.pre_deploy]
      command = "sops decrypt -i docker-compose.yaml"
    EOT
  ])
}

resource "github_repository_file" "komodo_stacks_docker_compose" {
  for_each = nonsensitive(toset(keys(local.komodo_services)))

  commit_message      = "Update ${each.value} SOPS-encrypted docker-compose"
  content             = shell_sensitive_script.komodo_service_compose_encrypt[each.value].output
  file                = "${each.value}/docker-compose.yaml"
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
