# Services layer - deploys services to infrastructure

# Get all service entries from 1Password
data "onepassword_vault" "services" {
  name = "Services"
}

# Get all services
locals {
  services = {
    for item in data.onepassword_vault.services.items :
    item.title => {
      title   = item.title
      id      = item.id
      tags    = toset(item.tags)
      url     = try(item.url, "")
      
      # Extract platform and service name
      platform = split("-", item.title)[0]
      service  = join("-", slice(split("-", item.title), 1, length(split("-", item.title))))
      
      # Service configuration will be loaded from 1Password
    } if can(regex("^(docker|fly|vercel)-", item.title)) && !contains(item.tags, "template")
  }
}

# TODO: Implement service deployments
# - Docker services via SSH/remote-exec
# - Fly.io services via fly provider
# - Vercel services via API
