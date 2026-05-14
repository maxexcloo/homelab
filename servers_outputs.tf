locals {
  _servers_outputs_runtime_addresses = {
    for server_key, server in local.servers_model : server_key => merge(
      server.addresses,
      {
        private_ipv4   = try(local.unifi_clients[server_key].fixed_ip, null)
        tailscale_ipv4 = try(local.tailscale_device_addresses[server_key].ipv4, null)
        tailscale_ipv6 = try(local.tailscale_device_addresses[server_key].ipv6, null)
      },
    )
  }

  _servers_outputs_runtime_hosts = {
    for server_key, server in local.servers_model : server_key => merge(
      server.hosts,
      {
        private   = try(local.unifi_clients[server_key].local_dns_record, null)
        tailscale = try(local.tailscale_device_addresses[server_key].address, null)
      },
    )
  }

  _servers_outputs_runtime_url_sources = {
    for server_key, server in local.servers_model : server_key => merge(
      local._servers_outputs_runtime_hosts[server_key],
      local._servers_outputs_runtime_addresses[server_key],
    )
  }

  _servers_outputs_runtime_urls = {
    for server_key, server in local.servers_model : server_key => merge(
      server.urls,
      {
        for url_label, url_value in local._servers_outputs_runtime_url_sources[server_key] : url_label => {
          href = format(
            "https://%s%s",
            can(cidrhost("${url_value}/128", 0)) ? "[${url_value}]" : url_value,
            server.networking.management_port != 443 ? ":${server.networking.management_port}" : ""
          )
          label = url_label
        }
        if !contains(keys(server.urls), url_label) && url_value != null && url_value != ""
      },
      {
        for url_label, url_value in local._servers_outputs_runtime_url_sources[server_key] : "${url_label}_ssh" => {
          href = format(
            "ssh://%s@%s%s",
            server.identity.username,
            can(cidrhost("${url_value}/128", 0)) ? "[${url_value}]" : url_value,
            server.networking.ssh_port != 22 ? ":${server.networking.ssh_port}" : ""
          )
          label = "${url_label}_ssh"
        }
        if url_label != "management" && url_value != null && url_value != ""
      },
    )
  }

  _servers_outputs_credentials_bootstrap = {
    for entry in flatten([
      for server_key, server in local.servers_model : [
        for field_name, field in server.credentials.fields : {
          key = "${server_key}-${field_name}"
          value = (
            field.bootstrap_type == "hex" ? random_id.server_secret["${server_key}-${field_name}"].hex
            : field.bootstrap_type == "base64" ? random_id.server_secret["${server_key}-${field_name}"].b64_std
            : field.bootstrap_type != null && contains(["alphanumeric", "string"], field.bootstrap_type) ? random_password.server_secret["${server_key}-${field_name}"].result
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
        runtime = {
          addresses = local._servers_outputs_runtime_addresses[server_key]

          attributes = merge(
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

          hosts = local._servers_outputs_runtime_hosts[server_key]

          urls = local._servers_outputs_runtime_urls[server_key]

          credentials = merge(
            {
              age_secret_key = age_secret_key.server[server_key].secret_key
              komodo_passkey = random_password.server_komodo_passkey[server_key].result
            },
            {
              for field_name, field in server.credentials.fields : field_name => sensitive(try(coalesce(
                try(local.onepassword_server_existing_fields[server_key][field_name], null),
                local._servers_outputs_credentials_bootstrap["${server_key}-${field_name}"],
              ), ""))
              if field.bootstrap_type != null || field.mode == "rw"
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
            server.features.password ? merge(
              {
                password = sensitive(coalesce(try(local.onepassword_server_existing_fields[server_key].password, null), random_password.server[server_key].result))
              },
              {
                password_hash = bcrypt_hash.server[server_key].id
              },
            ) : {},
            server.features.pushover ? {
              pushover_application_token = sensitive(try(local.onepassword_server_existing_fields[server_key].pushover_application_token, ""))
              pushover_user_key          = sensitive(try(local.onepassword_server_existing_fields[server_key].pushover_user_key, ""))
            } : {},
            server.features.resend ? {
              resend_api_key = jsondecode(restapi_object.resend_api_key_server[server_key].create_response).token
            } : {},
            server.features.tailscale ? {
              tailscale_auth_key = tailscale_tailnet_key.server[server_key].key
            } : {},
          )
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
