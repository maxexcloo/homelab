module "services" {
  source = "./modules/services"

  defaults = local.defaults
  dns      = local.dns_input

  integrations = {
    cloudflare = {
      account_id = data.cloudflare_account.default.id
      zone_ids   = local.cloudflare_zone_ids
    }

    pocketid = {
      enabled = local.defaults.pocketid.enabled
      ready   = local._pocketid_integration_ready
      url     = var.pocketid_url
    }

    tailscale_auth_keys = {
      for service_key, key in tailscale_tailnet_key.service :
      service_key => key.key
    }
  }

  providers = {
    restapi.resend = restapi.resend
  }

  servers = {
    age_public_keys = module.servers.infrastructure.age_public_keys
    item_ids        = module.servers.infrastructure.item_ids
    model           = module.servers.model
    render          = module.servers.render
    runtime         = module.servers.runtime
  }
}
