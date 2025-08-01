# Main infrastructure configuration

# Discover all infrastructure items from 1Password
data "onepassword_vault" "infrastructure" {
  name = "Infrastructure"
}

locals {
  # Get all items from vault
  vault_items = {
    for item in try(data.onepassword_vault.infrastructure.items, []) :
    item.title => item
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
    if can(regex("^server-", name))
  }
}

# Output for debugging
output "discovered_infrastructure" {
  value = {
    dns_zones = keys(local.dns_zones)
    routers   = keys(local.routers)
    servers   = keys(local.servers)
  }
  sensitive = false
}