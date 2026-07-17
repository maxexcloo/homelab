# Stage: runtime — merges provider-backed values into servers_model. Never used as for_each key.
locals {
  # Flat "server_key-credential_name" → generated scalar value table. Nested
  # resource for_each is not supported, so random.tf uses the same compound key.
  _servers_outputs_credentials_generated = {
    for credential_key, generator in local.random_server_credentials : credential_key => (
      generator.type == "hex" ? random_id.server_secret[credential_key].hex
      : generator.type == "base64" ? random_id.server_secret[credential_key].b64_std
      : contains(["alphanumeric", "string"], generator.type) ? random_password.server_secret[credential_key].result
      : null
    )
  }

  # Static model addresses plus runtime-discovered private and Tailscale IPs.
  _servers_outputs_runtime_addresses = {
    for server_key, server in local.servers_model : server_key => merge(
      server.addresses,
      {
        private_ipv4   = try(local.unifi_clients[server_key].fixed_ip, "")
        tailscale_ipv4 = try(local.tailscale_device_addresses[server_key].ipv4, "")
        tailscale_ipv6 = try(local.tailscale_device_addresses[server_key].ipv6, "")
      },
    )
  }

  # Static model hostnames plus runtime-discovered private and Tailscale hostnames.
  _servers_outputs_runtime_hosts = {
    for server_key, server in local.servers_model : server_key => merge(
      server.hosts,
      {
        private   = try(local.unifi_clients[server_key].local_dns_record, "")
        tailscale = try(local.tailscale_device_addresses[server_key].address, "")
      },
    )
  }

  _servers_outputs_runtime_url_sources = {
    for server_key, server in local.servers_model : server_key => {
      for url_label, url_value in merge(
        local._servers_outputs_runtime_hosts[server_key],
        local._servers_outputs_runtime_addresses[server_key],
      ) : url_label => url_value
      if(
        url_value != null &&
        url_value != ""
      )
    }
  }

  # Addresses are bracket-wrapped when they are IPv6 literals.
  _servers_outputs_runtime_urls = {
    for server_key, server in local.servers_model : server_key => merge(
      server.urls,
      {
        for url_label, url_value in local._servers_outputs_runtime_url_sources[server_key] : url_label => {
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
        for url_label, url_value in local._servers_outputs_runtime_url_sources[server_key] : "${url_label}_ssh" => {
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
          addresses = local._servers_outputs_runtime_addresses[server_key]
          hosts     = local._servers_outputs_runtime_hosts[server_key]
          urls      = local._servers_outputs_runtime_urls[server_key]

          attributes = merge(
            {
              age_public_key        = age_secret_key.server[server_key].public_key
              cloudflare_account_id = data.cloudflare_account.default.id
              ssh_keys              = data.github_user.default.ssh_keys
              tailscale_device_id   = try(local.tailscale_device_addresses[server_key].id, "")
            },
            server.features.b2 ? {
              b2_application_key_id = b2_application_key.server[server_key].application_key_id
              b2_bucket_name        = b2_bucket.server[server_key].bucket_name
              b2_endpoint           = local.b2_endpoint
            } : {},
            server.features.cloudflared ? {
              cloudflare_tunnel_id = module.cloudflare_tunnel[server_key].tunnel_id
            } : {},
          )

          credentials = merge(
            {
              age_secret_key = age_secret_key.server[server_key].secret_key
            },
            {
              for field_name, field in server.credentials.fields : field_name => sensitive(try(coalesce(
                try(local.onepassword_server_existing_fields[server_key][field_name], null),
                try(local._servers_outputs_credentials_generated["${server_key}-${field_name}"], null),
              ), ""))
              if field.mode == "rw"
            },
            server.features.b2 ? {
              b2_application_key = b2_application_key.server[server_key].application_key
            } : {},
            server.features.cloudflare_acme ? {
              cloudflare_acme_token = cloudflare_account_token.server_acme[server_key].value
            } : {},
            server.features.cloudflare_acme_legacy ? {
              cloudflare_acme_legacy_token = cloudflare_account_token.server_acme_legacy[server_key].value
            } : {},
            server.features.cloudflared ? {
              cloudflare_tunnel_read_token = module.cloudflare_tunnel[server_key].tunnel_read_token
              cloudflare_tunnel_token      = module.cloudflare_tunnel[server_key].tunnel_token
            } : {},
            server.features.password ? {
              password      = sensitive(coalesce(try(local.onepassword_server_existing_fields[server_key].password, null), random_password.server_secret["${server_key}-password"].result))
              password_hash = bcrypt_hash.server[server_key].id
            } : {},
            server.features.resend ? {
              resend_api_key = jsondecode(restapi_object.resend_api_key_server[server_key].create_response).token
            } : {},
            server.features.tailscale ? {
              tailscale_auth_key = tailscale_tailnet_key.server[server_key].key
            } : {},
            merge({}, [
              for credential_name, generator in server.credentials.generated : generator.type == "x509" ? {
                "${credential_name}_certificate" = tls_self_signed_cert.server["${server_key}-${credential_name}"].cert_pem
                "${credential_name}_private_key" = tls_private_key.server["${server_key}-${credential_name}"].private_key_pem
              } : {}
            ]...),
          )
        }
      },
    )
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
      if(
        field_value != null &&
        field_value != "" &&
        field_value != false
      )
    }
  }
}
