locals {
  fly_services = {
    for k, v in local.services : k => v
    if v.server == "fly"
  }
}

resource "github_repository_file" "fly_configs" {
  for_each = local.fly_services

  commit_message      = "Update ${each.key} Fly.io configuration"
  file                = "${each.key}/fly.toml"
  overwrite_on_create = true
  repository          = local.defaults.github.repositories.fly

  content = templatefile("${path.module}/templates/fly/fly.toml", {
    defaults = local.defaults
    servers  = local.servers
    service  = each.value
    services = local.services
  })
}
