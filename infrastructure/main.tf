# Main infrastructure configuration

# Discover all infrastructure items from 1Password using op CLI
data "external" "infrastructure_vault_items" {
  program = ["sh", "-c", "op item list --vault='${var.onepassword_vault_infrastructure}' --format=json | jq -c '{stdout: .}'"]
}

data "external" "services_vault_items" {
  program = ["sh", "-c", "op item list --vault='Services' --format=json | jq -c '{stdout: .}'"]
}

locals {
  # Parse vault items from op CLI output
  vault_items = {
    for item in jsondecode(data.external.infrastructure_vault_items.result.stdout) :
    item.title => {
      id    = item.id
      title = item.title
      tags  = try(item.tags, [])
      urls  = try(item.urls, [])
    }
  }

  # Filter DNS zones
  dns_zones = {
    for name, item in local.vault_items :
    replace(name, "dns-", "") => item
    if can(regex("^dns-", name))
  }

  # Filter routers
  routers = {
    for name, item in local.vault_items :
    replace(name, "router-", "") => item
    if can(regex("^router-", name))
  }

  # Filter servers
  servers = {
    for name, item in local.vault_items :
    name => item
    if can(regex("^server-", name)) && !contains(item.tags, "template")
  }
}

# Load detailed server configurations from 1Password
data "onepassword_item" "server" {
  for_each = local.servers

  vault = var.onepassword_vault_infrastructure
  title = each.key
}

# Extract Proxmox server configurations for manual provider setup
locals {
  # Get all proxmox-* sections from providers entry
  proxmox_servers = {
    for section in try(data.onepassword_item.providers.section, []) :
    replace(section.label, "proxmox-", "") => {
      for field in section.field :
      field.label => field.value
    } if can(regex("^proxmox-", section.label))
  }

  # Parse service items from op CLI output
  services = {
    for item in jsondecode(data.external.services_vault_items.result.stdout) :
    item.title => {
      title    = item.title
      id       = item.id
      tags     = toset(try(item.tags, []))
      url      = try(length(item.urls) > 0 ? item.urls[0].href : "", "")
      platform = split("-", item.title)[0]
      service  = join("-", slice(split("-", item.title), 1, length(split("-", item.title))))
    } if can(regex("^(docker|fly|vercel|cf)-", item.title)) && !contains(try(item.tags, []), "template")
  }
}

# # Create servers using module
# module "server" {
#   source = "../modules/server"

#   for_each = local.servers

#   name   = each.key
#   config = data.onepassword_item.server[each.key]
# }

# Output for debugging
output "discovered_infrastructure" {
  value = {
    dns_zones = keys(local.dns_zones)
    routers   = keys(local.routers)
    servers   = keys(local.servers)
    services  = keys(local.services)
  }
  sensitive = false
}

# Output Proxmox provider configurations for manual setup
output "proxmox_provider_configs" {
  description = "Proxmox provider configurations extracted from 1Password"
  value = {
    for server_name, config in local.proxmox_servers :
    server_name => {
      # Extract host and port from endpoint
      endpoint_url = config.endpoint
      host         = regex("^https?://([^:]+)", config.endpoint)[0]
      port         = try(regex(":([0-9]+)", config.endpoint)[0], "8006")
      
      # Extract username without @pam suffix
      ssh_username = replace(config.username, "@pam", "")
      username     = config.username
      password     = config.password
      
      # Default to insecure=true for self-signed certificates
      insecure = try(config.insecure, "true") == "true"
      
      # Generated provider configuration
      provider_config = <<-EOT
        provider "proxmox" {
          alias    = "${server_name}"
          endpoint = "${config.endpoint}"
          insecure = ${try(config.insecure, "true") == "true"}
          password = "${config.password}"
          username = "${config.username}"

          ssh {
            agent    = true
            username = "${replace(config.username, "@pam", "")}"

            node {
              address = "${regex("^https?://([^:]+)", config.endpoint)[0]}"
              name    = "${server_name}"
            }
          }
        }
      EOT
    }
  }
  sensitive = true
}

# # Output server details
# output "servers" {
#   value = {
#     for name, server in module.server :
#     name => server.server
#   }
#   sensitive = false
# }
