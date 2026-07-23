module "servers" {
  source = "./modules/servers"

  defaults = local.defaults
  dns      = local.dns_input

  integrations = {
    cloudflare = {
      account_id = data.cloudflare_account.default.id
      dns_write_permission_group_id = one(
        data.cloudflare_account_api_token_permission_groups_list.dns_write.result,
      ).id
      tunnel_read_permission_group_id = one(
        data.cloudflare_account_api_token_permission_groups_list.tunnel_read.result,
      ).id
      zone_ids = {
        for zone_name, zone in data.cloudflare_zone.all :
        zone_name => zone.zone_id
      }
    }

    github = {
      docker_repository = github_repository.deployment["docker"].name
      ssh_keys          = data.github_user.default.ssh_keys
    }

    onepassword = {
      connect_url     = var.onepassword_connect_url
      enabled         = local._onepassword_integration_enabled
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
    tailscale_device_addresses = local.tailscale_device_addresses
  }

  providers = {
    restapi.onepassword = restapi.onepassword
    restapi.resend      = restapi.resend
  }
}
