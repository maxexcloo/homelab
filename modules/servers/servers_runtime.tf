# Stage: runtime — merges provider-backed values into servers_model. Never used as for_each key.
locals {
  # Static model addresses plus runtime-discovered private and Tailscale IPs.
  _servers_runtime_addresses = {
    for server_key, server in local.servers_model : server_key => merge(
      server.addresses,
      {
        private_ipv4   = try(data.unifi_client.server[server_key].fixed_ip, "")
        tailscale_ipv4 = try(local.tailscale_device_addresses[server_key].ipv4, "")
        tailscale_ipv6 = try(local.tailscale_device_addresses[server_key].ipv6, "")
      },
    )
  }

  # Static model hostnames plus runtime-discovered private and Tailscale hostnames.
  _servers_runtime_hosts = {
    for server_key, server in local.servers_model : server_key => merge(
      server.hosts,
      {
        private   = try(data.unifi_client.server[server_key].local_dns_record, "")
        tailscale = try(local.tailscale_device_addresses[server_key].address, "")
      },
    )
  }

  _servers_runtime_url_sources = {
    for server_key, server in local.servers_model : server_key => {
      for url_label, url_value in merge(
        local._servers_runtime_hosts[server_key],
        local._servers_runtime_addresses[server_key],
      ) : url_label => url_value
      if(
        url_value != null &&
        url_value != ""
      )
    }
  }

  # Addresses are bracket-wrapped when they are IPv6 literals.
  _servers_runtime_urls = {
    for server_key, server in local.servers_model : server_key => merge(
      server.urls,
      {
        for url_label, url_value in local._servers_runtime_url_sources[server_key] : url_label => {
          label = url_label

          href = (
            server.networking.management_port != "" &&
            server.networking.management_port != 443
            ) ? format(
            "https://%s:%s",
            can(cidrhost("${url_value}/128", 0)) ? "[${url_value}]" : url_value,
            server.networking.management_port,
            ) : format(
            "https://%s",
            can(cidrhost("${url_value}/128", 0)) ? "[${url_value}]" : url_value,
          )
        }
        if !can(server.urls[url_label])
      },
      {
        for url_label, url_value in local._servers_runtime_url_sources[server_key] : "${url_label}_ssh" => {
          label = "${url_label}_ssh"

          href = format(
            "ssh://%s@%s%s",
            server.identity.username,
            can(cidrhost("${url_value}/128", 0)) ? "[${url_value}]" : url_value,
            server.networking.ssh_port != 22 ? ":${server.networking.ssh_port}" : ""
          )
        }
        if(
          url_label != "management" &&
          server.identity.username != ""
        )
      },
    )
  }

  # Full runtime server object. Never used as a for_each key — use servers_model instead.
  servers = {
    for server_key, server in local.servers_model : server_key => merge(
      server,
      {
        runtime = {
          addresses = local._servers_runtime_addresses[server_key]
          hosts     = local._servers_runtime_hosts[server_key]
          urls      = local._servers_runtime_urls[server_key]

          attributes = merge(
            {
              age_public_key        = age_secret_key.server[server_key].public_key
              cloudflare_account_id = var.integrations.cloudflare.account_id
              ssh_keys              = var.integrations.github.ssh_keys
              tailscale_device_id   = try(local.tailscale_device_addresses[server_key].id, "")
            },
            server.features.cloudflared ? {
              cloudflare_tunnel_id = cloudflare_zero_trust_tunnel_cloudflared.server[server_key].id
            } : {},
            server.features.mail ? {
              mail_host     = local.defaults.resend.host
              mail_port     = local.defaults.resend.port
              mail_username = local.defaults.resend.username
            } : {},
            server.features.object_storage ? {
              object_storage_access_key_id = module.object_storage.items[server_key].access_key_id
              object_storage_bucket        = module.object_storage.items[server_key].bucket
              object_storage_endpoint      = module.object_storage.items[server_key].endpoint
            } : {},
          )

          credentials = merge(
            {
              age_secret_key = age_secret_key.server[server_key].secret_key
            },
            {
              for field_name, field in server.credentials.fields : field_name => sensitive(try(coalesce(
                try(local.onepassword_server_existing_fields[server_key][field_name], null),
                try(module.credentials.values["${server_key}-${field_name}"], null),
              ), ""))
              if field.mode == "rw"
            },
            server.features.cloudflare_acme ? {
              cloudflare_acme_token = cloudflare_account_token.server_acme[server_key].value
            } : {},
            server.features.cloudflare_acme_legacy ? {
              cloudflare_acme_legacy_token = cloudflare_account_token.server_acme_legacy[server_key].value
            } : {},
            server.features.cloudflared ? {
              cloudflare_tunnel_read_token = cloudflare_account_token.server_tunnel_read[server_key].value
              cloudflare_tunnel_token      = data.cloudflare_zero_trust_tunnel_cloudflared_token.server[server_key].token
            } : {},
            server.features.mail ? {
              mail_password = jsondecode(restapi_object.resend_api_key_server[server_key].create_response).token
            } : {},
            server.features.object_storage ? {
              object_storage_secret_access_key = module.object_storage.items[server_key].secret_access_key
            } : {},
            server.features.password ? {
              password      = module.credentials.passwords[server_key].value
              password_hash = module.credentials.passwords[server_key].hash
            } : {},
            server.features.tailscale ? {
              tailscale_auth_key = var.integrations.tailscale_auth_keys[server_key]
            } : {},
            merge({}, [
              for credential_name, generator in server.credentials.generated : {
                "${credential_name}_certificate" = module.credentials.x509["${server_key}-${credential_name}"].certificate
                "${credential_name}_private_key" = module.credentials.x509["${server_key}-${credential_name}"].private_key
              }
              if generator.type == "x509"
            ]...),
          )
        }
      },
    )
  }
}
