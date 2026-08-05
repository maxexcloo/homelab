module "servers" {
  source = "./modules/servers"

  defaults = local.defaults
  dns      = local.dns_input

  integrations = {
    tailscale_device_addresses = local.tailscale_device_addresses

    cloudflare = {
      account_id = data.cloudflare_account.default.id
      zone_ids   = local.cloudflare_zone_ids
    }

    github = {
      docker_repository = github_repository.deployment["docker"].name
      packages_token    = var.homelab_packages_token
    }

    oci = {
      always_free  = var.oci_always_free
      tenancy_ocid = var.oci_tenancy_ocid
    }

    tailscale_auth_keys = {
      for server_key, key in tailscale_tailnet_key.server :
      server_key => key.key
    }
  }

  providers = {
    restapi.resend = restapi.resend
  }
}
