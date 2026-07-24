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
    }

    onepassword = {
      connect_url     = var.onepassword_connect_url
      enabled         = local.defaults.onepassword.enabled
      ready           = local._onepassword_integration_ready
      request_headers = local.onepassword_connect_request_headers
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
    restapi.onepassword = restapi.onepassword
    restapi.resend      = restapi.resend
  }
}
