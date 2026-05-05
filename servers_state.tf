locals {
  servers_state = {
    for server_key, server in local.servers_input : server_key => {
      fields = merge(
        {
          age_public_key        = age_secret_key.server[server_key].public_key
          cloudflare_account_id = data.cloudflare_account.default.id
          tailscale_device_id   = try(local.tailscale_device_addresses[server_key].id, null)
        },
        server.features.b2 ? {
          b2_application_key_id = b2_application_key.server[server_key].application_key_id
          b2_bucket_name        = b2_bucket.server[server_key].bucket_name
          b2_endpoint           = local.b2_endpoint
        } : {},
        server.features.cloudflare_zero_trust_tunnel ? {
          cloudflare_tunnel_id = module.cloudflare_tunnel[server_key].tunnel_id
        } : {},
      )

      secrets = merge(
        {
          age_secret_key = age_secret_key.server[server_key].secret_key
        },
        server.features.b2 ? {
          b2_application_key = b2_application_key.server[server_key].application_key
        } : {},
        server.features.cloudflare_acme_token ? {
          cloudflare_acme_token = cloudflare_account_token.server_acme[server_key].value
        } : {},
        server.features.cloudflare_zero_trust_tunnel ? {
          cloudflare_tunnel_read_token = module.cloudflare_tunnel[server_key].tunnel_read_token
          cloudflare_tunnel_token      = module.cloudflare_tunnel[server_key].tunnel_token
        } : {},
        server.features.password ? {
          password      = sensitive(try(local.onepassword_server_existing_fields[server_key].password, random_password.server[server_key].result))
          password_hash = bcrypt_hash.server[server_key].id
        } : {},
        server.features.pushover ? {
          pushover_application_token = var.pushover_application_token
          pushover_user_key          = var.pushover_user_key
        } : {},
        server.features.resend ? {
          resend_api_key = jsondecode(restapi_object.resend_api_key_server[server_key].create_response).token
        } : {},
        server.features.tailscale ? {
          tailscale_auth_key = tailscale_tailnet_key.server[server_key].key
        } : {},
      )

      ssh_keys = data.github_user.default.ssh_keys

      urls = {
        fqdn_external      = local.servers_model[server_key].fqdn_external
        fqdn_internal      = local.servers_model[server_key].fqdn_internal
        management_address = server.networking.management_address
        private_address    = try(local.unifi_clients[server_key].local_dns_record, null)
        private_ipv4       = try(local.unifi_clients[server_key].fixed_ip, null)
        public_address     = local.servers_model[server_key].public_address
        public_ipv4        = local.servers_model[server_key].public_ipv4
        public_ipv6        = local.servers_model[server_key].public_ipv6
        tailscale_hostname = try(local.tailscale_device_addresses[server_key].hostname, null)
        tailscale_ipv4     = try(local.tailscale_device_addresses[server_key].ipv4, null)
        tailscale_ipv6     = try(local.tailscale_device_addresses[server_key].ipv6, null)
      }
    }
  }
}
