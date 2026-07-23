locals {
  docker_webhook_servers = {
    for server_key, server in local.servers_model : server_key => server
    if(
      server.features.docker &&
      anytrue([
        for route in server.routing.routes :
        route.expose == "cloudflare" && route.host == "doco-cd.${server.hosts.external}"
      ])
    )
  }
}

resource "github_repository_webhook" "doco_cd" {
  for_each = local.docker_webhook_servers

  active     = true
  events     = ["push"]
  repository = var.integrations.github.docker_repository

  configuration {
    content_type = "json"
    insecure_ssl = false
    secret       = local.servers[each.key].runtime.credentials.doco_cd_webhook_secret
    url          = "https://doco-cd.${each.value.hosts.external}/v1/webhook/${each.key}"
  }
}
