# Main infrastructure configuration

# Discover all infrastructure items from 1Password using op CLI
data "external" "infrastructure_vault_items" {
  program = ["sh", "-c", "op item list --vault='${var.onepassword_vault}' --format=json | jq -c '{stdout: (. | tostring)}'"]
}

locals {
  # Parse vault items from op CLI output
  vault_items = {
    for item in jsondecode(data.external.infrastructure_vault_items.result.stdout) : item.title => {
      id    = item.id
      tags  = try(item.tags, [])
      title = item.title
      urls  = try(item.urls, [])
    }
  }

  # Filter routers
  routers = {
    for name, item in local.vault_items : replace(name, "router-", "") => item
    if can(regex("^router-", name))
  }

  # Filter servers
  servers = {
    for name, item in local.vault_items : replace(name, "server-", "") => item
    if can(regex("^server-", name))
  }
}

# Load detailed server configurations from 1Password
data "onepassword_item" "server" {
  for_each = local.servers

  vault = var.onepassword_vault
  title = each.key
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
    routers = keys(local.routers)
    servers = keys(local.servers)
  }
  sensitive = false
}

# # Output server details
# output "servers" {
#   value = {
#     for name, server in module.server :
#     name => server.server
#   }
#   sensitive = false
# }
