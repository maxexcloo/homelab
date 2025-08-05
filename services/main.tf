# Services layer - deploys services to infrastructure

# Get infrastructure data for server access
data "onepassword_vault" "infrastructure" {
  name = "Infrastructure"
}

# Get all service entries from 1Password
data "onepassword_vault" "services" {
  name = "Services"
}

# Get servers from infrastructure vault
locals {
  # Filter servers from infrastructure vault
  servers = {
    for item in data.onepassword_vault.infrastructure.items :
    item.title => {
      title = item.title
      id    = item.id
      tags  = toset(item.tags)
    } if can(regex("^server-", item.title)) && !contains(item.tags, "template")
  }

  # Get all services
  services = {
    for item in data.onepassword_vault.services.items :
    item.title => {
      title = item.title
      id    = item.id
      tags  = toset(item.tags)
      url   = try(item.url, "")

      # Extract platform and service name
      platform = split("-", item.title)[0]
      service  = join("-", slice(split("-", item.title), 1, length(split("-", item.title))))

      # Service configuration will be loaded from 1Password
    } if can(regex("^(docker|fly|vercel)-", item.title)) && !contains(item.tags, "template")
  }
}

# Load detailed server configurations from 1Password for username/password inheritance
data "onepassword_item" "server" {
  for_each = local.servers

  vault = "Infrastructure"
  title = each.key
}

# Output server configurations for debugging
output "servers" {
  description = "Available servers for service deployment"
  value = {
    for name, server in data.onepassword_item.server :
    name => {
      # Extract deployment-relevant information
      platform = try([for section in server.section : section.label if contains(["inputs", "oci", "proxmox"], section.label)][0], "unknown")

      # Extract username/password for Docker deployments
      username = try([
        for section in server.section :
        [for field in section.field : field.value if field.label == "username"][0]
        if section.label == "inputs"
      ][0], "")

      password = try([
        for section in server.section :
        [for field in section.field : field.value if field.label == "password"][0]
        if section.label == "inputs"
      ][0], "")

      # Extract connection details
      host = try([
        for section in server.section :
        [for field in section.field : field.value if field.label == "host"][0]
        if contains(["inputs", "oci", "proxmox"], section.label)
      ][0], "")
    }
  }
  sensitive = true
}

# TODO: Implement service deployments
# - Docker services via SSH/remote-exec using server credentials
# - Fly.io services via API
# - Vercel services via API
