locals {
  _servers_outputs_secret_bootstrap = {
    for entry in flatten([
      for server_key, server in local.servers_model : [
        for secret in server.secrets : {
          key = "${server_key}-${secret.name}"
          value = (
            secret.bootstrap_type == "hex" ? random_id.server_secret["${server_key}-${secret.name}"].hex
            : secret.bootstrap_type == "base64" ? random_id.server_secret["${server_key}-${secret.name}"].b64_std
            : secret.bootstrap_type != null && contains(["alphanumeric", "string"], secret.bootstrap_type) ? random_password.server_secret["${server_key}-${secret.name}"].result
            : null
          )
        }
      ]
    ]) : entry.key => entry.value
  }

  servers = {
    for server_key, server in local.servers_model : server_key => merge(
      server,
      {
        state = {
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
              komodo_passkey = random_password.server_komodo_passkey[server_key].result
            },
            {
              for secret in server.secrets : secret.name => sensitive(try(coalesce(
                try(local.onepassword_server_existing_fields[server_key][secret.name], null),
                local._servers_outputs_secret_bootstrap["${server_key}-${secret.name}"],
              ), ""))
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
              password      = sensitive(coalesce(try(local.onepassword_server_existing_fields[server_key]["password"], null), random_password.server[server_key].result))
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

          urls = {
            fqdn_external      = server.fqdn_external
            fqdn_internal      = server.fqdn_internal
            management_address = server.networking.management_address
            private_address    = try(local.unifi_clients[server_key].local_dns_record, null)
            private_ipv4       = try(local.unifi_clients[server_key].fixed_ip, null)
            public_address     = server.public_address
            public_ipv4        = server.public_ipv4
            public_ipv6        = server.public_ipv6
            tailscale_address  = try(local.tailscale_device_addresses[server_key].address, null)
            tailscale_ipv4     = try(local.tailscale_device_addresses[server_key].ipv4, null)
            tailscale_ipv6     = try(local.tailscale_device_addresses[server_key].ipv6, null)
          }
        }
      },
    )
  }

  servers_by_feature = {
    for feature in keys(local.defaults.servers.features) : feature => {
      for server_key, server in local.servers_model : server_key => server
      if server.features[feature]
    }
  }
}

output "servers" {
  description = "Server configurations"
  sensitive   = true

  # Top-level false/null/empty defaults are filtered out to reduce output noise.
  # Nested objects keep their full schema shape.
  value = {
    for server_key, server in local.servers : server_key => {
      for field_name, field_value in server : field_name => field_value
      if field_value != null && field_value != "" && field_value != false
    }
  }
}
