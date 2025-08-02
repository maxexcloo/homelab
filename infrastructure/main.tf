# Main infrastructure configuration

# Discover all infrastructure items from 1Password
data "onepassword_vault" "infrastructure" {
  name = var.onepassword_vault_infrastructure
}

locals {
  # Get all items from vault - TODO: Fix onepassword_vault data source
  vault_items = {
    # for item in try(data.onepassword_vault.infrastructure.items, []) :
    # item.title => item
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

# TODO: Load detailed server configurations from 1Password
# data "onepassword_item" "server" {
#   for_each = local.servers
#
#   vault = data.onepassword_vault.infrastructure.name
#   title = each.key
# }

# Discover services for DNS configuration
data "onepassword_vault" "services" {
  name = "Services"
}

locals {
  # Get all service items - TODO: Fix onepassword_vault data source
  services = {
    # for item in try(data.onepassword_vault.services.items, []) :
    # item.title => {
    #   title    = item.title
    #   id       = item.id
    #   tags     = toset(item.tags)
    #   url      = try(item.url, "")
    #   platform = split("-", item.title)[0]
    #   service  = join("-", slice(split("-", item.title), 1, length(split("-", item.title))))
    # } if can(regex("^(docker|fly|vercel|cf)-", item.title)) && !contains(item.tags, "template")
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

# # Output server details
# output "servers" {
#   value = {
#     for name, server in module.server :
#     name => server.server
#   }
#   sensitive = false
# }
