module "services" {
  source = "./modules/services"

  defaults = local.defaults
  dns      = local.dns_input

  integrations = {
    debug_dir = var.debug_dir

    cloudflare = {
      account_id = data.cloudflare_account.default.id
      zone_ids   = local.cloudflare_zone_ids
    }

    github = {
      workflow_revisions = local.github_workflow_revisions

      repositories = {
        for repository_key, repository in github_repository.deployment :
        repository_key => repository.name
      }
    }

    onepassword = {
      connect_url     = var.onepassword_connect_url
      enabled         = local._onepassword_integration_enabled
      ready           = local._onepassword_integration_ready
      request_headers = local.onepassword_connect_request_headers
    }

    pocketid = {
      enabled = local._pocketid_integration_enabled
      ready   = local._pocketid_integration_ready
      url     = var.pocketid_url
    }

    tailscale_auth_keys = {
      for service_key, key in tailscale_tailnet_key.service :
      service_key => key.key
    }
  }

  providers = {
    restapi.onepassword = restapi.onepassword
    restapi.resend      = restapi.resend
  }

  servers = {
    age_public_keys = module.servers.infrastructure.age_public_keys
    model           = module.servers.model
    render          = module.servers.render
    runtime         = module.servers.runtime
  }
}
