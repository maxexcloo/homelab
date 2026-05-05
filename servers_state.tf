locals {
  # 1Password STRING fields (non-sensitive scalars). Feature-gated entries
  # default to null and get overwritten when the feature is on.
  _servers_state_fields = {
    for server_key, server in local.servers_input : server_key => merge(
      {
        age_public_key        = age_secret_key.server[server_key].public_key
        b2_application_key_id = null
        b2_bucket_name        = null
        b2_endpoint           = null
        cloudflare_account_id = data.cloudflare_account.default.id
        cloudflare_tunnel_id  = null
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
  }

  # 1Password CONCEALED fields (sensitive scalars). Feature-gated entries
  # default to null and get overwritten when the feature is on.
  _servers_state_secrets = {
    for server_key, server in local.servers_input : server_key => merge(
      {
        age_secret_key               = age_secret_key.server[server_key].secret_key
        b2_application_key           = null
        cloudflare_acme_token        = null
        cloudflare_tunnel_read_token = null
        cloudflare_tunnel_token      = null
        password                     = null
        password_hash                = null
        pushover_application_token   = null
        pushover_user_key            = null
        resend_api_key               = null
        tailscale_auth_key           = null
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
  }

  # 1Password URL items. Mirrors model FQDN/public addresses and adds runtime
  # private/tailscale addresses; null entries are filtered out at the consumer.
  _servers_state_urls = {
    for server_key, server in local.servers_input : server_key => {
      fqdn_external      = local.servers_model[server_key].fqdn_external
      fqdn_internal      = local.servers_model[server_key].fqdn_internal
      management_address = server.networking.management_address
      private_address    = try(local.unifi_clients[server_key].local_dns_record, null)
      private_ipv4       = try(local.unifi_clients[server_key].fixed_ip, null)
      public_address     = local.servers_model[server_key].public_address
      public_ipv4        = local.servers_model[server_key].public_ipv4
      public_ipv6        = local.servers_model[server_key].public_ipv6
      tailscale_ipv4     = try(local.tailscale_device_addresses[server_key].ipv4, null)
      tailscale_ipv6     = try(local.tailscale_device_addresses[server_key].ipv6, null)
    }
  }

  # Runtime server state. Iterated by 1Password sync via the three sub-objects;
  # ssh_keys is template-only (not synced).
  servers_state = {
    for server_key, server in local.servers_input : server_key => {
      fields   = local._servers_state_fields[server_key]
      secrets  = local._servers_state_secrets[server_key]
      ssh_keys = data.github_user.default.ssh_keys
      urls     = local._servers_state_urls[server_key]
    }
  }
}
