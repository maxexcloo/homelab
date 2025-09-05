locals {
  # Get all unique deployment targets from services
  komodo_homelab = {
    for k, v in local.homelab : k => v
    if contains(v.tags, "komodo")
  }

  komodo_services = {
    for k, v in local.services : k => v
    if length(v.targets) > 0 && v.platform == "docker"
  }

  # Render docker-compose templates with minimal template variables (KISS approach)
  komodo_services_templates = {
    for k, v in local.komodo_services : k => templatefile("${path.module}/docker/${k}/docker-compose.yaml",
      {
        # Default values (non-secrets only)
        default = {
          email        = var.default_email
          organisation = var.default_organization
          timezone     = var.default_timezone
        }

        # Service values (including secrets for SOPS encryption)
        service = {
          # Core identifiers
          fqdn     = coalesce(v.fqdn_external, v.fqdn_internal, "${k}.${var.domain_internal}")
          title    = title(replace(k, "-", " "))
          url      = "https://${coalesce(v.fqdn_external, v.fqdn_internal, "${k}.${var.domain_internal}")}"
          username = try(v.username, "admin")
          zone     = v.fqdn_external != null ? "external" : "internal"

          # Server-inherited secrets (will be encrypted by SOPS)
          b2_application_key    = try(length(v.targets) > 0 ? local.homelab[v.targets[0]].b2_application_key : "", "")
          b2_application_key_id = try(length(v.targets) > 0 ? local.homelab[v.targets[0]].b2_application_key_id : "", "")
          b2_bucket_name        = try(length(v.targets) > 0 ? local.homelab[v.targets[0]].b2_bucket_name : "", "")
          b2_endpoint           = try(length(v.targets) > 0 ? local.homelab[v.targets[0]].b2_endpoint : "", "")
          resend_api_key        = try(length(v.targets) > 0 ? local.homelab[v.targets[0]].resend_api_key : "", "")
        }
      }
    )
  }
}

# Encrypt docker-compose files using shell provider with SOPS (no temp files)
resource "shell_sensitive_script" "komodo_service_compose_encrypt" {
  for_each = nonsensitive(toset(keys(local.komodo_services)))

  environment = {
    AGE_PUBLIC_KEY = local.homelab[local.komodo_services[each.value].targets[0]].age_public_key
    CONTENT        = base64encode(local.komodo_services_templates[each.value])
  }

  lifecycle_commands {
    create = "echo '$CONTENT | base64 -d | sops -e --input-type yaml --output-type yaml --age '$AGE_PUBLIC_KEY' /dev/stdin"
    delete = "true"
    read   = "echo '$CONTENT | base64 -d | sops -e --input-type yaml --output-type yaml --age '$AGE_PUBLIC_KEY' /dev/stdin"
    update = "echo '$CONTENT | base64 -d | sops -e --input-type yaml --output-type yaml --age '$AGE_PUBLIC_KEY' /dev/stdin"

  }

  triggers = {
    age_public_key_hash = sha256(local.homelab[local.komodo_services[each.value].targets[0]].age_public_key)
    content_hash        = sha256(local.komodo_services_templates[each.value])
  }
}

# Generate ResourceSync configuration for Komodo
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

# Generate servers.toml with all deployment targets
resource "github_repository_file" "komodo_servers" {
  commit_message      = "Update Komodo server configurations"
  file                = "servers.toml"
  overwrite_on_create = true
  repository          = var.komodo_repository

  content = join("\n\n", [
    for k, v in local.komodo_homelab : <<-EOT
      [[server]]
      description = "${v.description}"
      name = "${k}"
      tags = [${join(", ", [for tag in v.tags : "\"${tag}\""])}]

      [server.config]
      address = "http://${v.fqdn_internal}:8120"
      enabled = true
      region = "${v.region}"
    EOT
  ])
}

# Generate Komodo Stack configurations for each service
resource "github_repository_file" "komodo_stacks" {
  commit_message      = "Update Komodo stack configurations"
  file                = "stacks.toml"
  overwrite_on_create = true
  repository          = var.komodo_repository

  content = join("\n\n", [
    for k, v in local.komodo_services : <<-EOT
      [[stack]]
      description = "${v.description}"
      name = "${k}"
      tags = [${join(", ", [for tag in concat(v.tags, [v.platform]) : "\"${tag}\""])}]

      [stack.config]
      auto_update = true
      repo = "${data.github_user.default.login}${var.komodo_repository}"
      run_directory = "${k}"
      server = "${v.targets[0]}"

      [stack.config.pre_deploy]
      command = "sops -d -i docker-compose.yaml"
    EOT
  ])
}

# Commit encrypted docker-compose files to GitHub
resource "github_repository_file" "komodo_stacks_docker_compose" {
  for_each = nonsensitive(toset(keys(local.komodo_services)))

  commit_message      = "Update ${each.value} SOPS-encrypted docker-compose"
  content             = shell_sensitive_script.komodo_service_compose_encrypt[each.value].output
  file                = "${each.value}/docker-compose.yaml"
  overwrite_on_create = true
  repository          = var.komodo_repository
}

# Generate variables.toml for shared configuration
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
