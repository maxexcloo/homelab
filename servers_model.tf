locals {
  # Deterministic computed fields derived from YAML input and ancestor chains.
  # Kept as a focused local so the desired model below can reference them
  # without repeating expressions.
  servers_model_computed = {
    for server_key, server in local.servers_input : server_key => {
      fqdn       = server.identity.name == server.identity.region ? server.identity.name : "${server.identity.name}.${server.identity.region}"
      type_icon  = local.defaults.types[server.type].icon
      type_label = local.defaults.types[server.type].label

      description = (
        server.parent == "" ? server.identity.title :
        try(server.identity.region == local.servers_input[server.parent].identity.name, false)
        ? "${server.identity.title} (${upper(server.identity.region)})"
        : "${try(local.servers_input[server.parent].identity.title, server.parent)} ${server.identity.title} (${upper(server.identity.region)})"
      )

      # Public addresses inherit from self, then parent, then grandparent; the
      # first non-empty valid value wins.
      public_address = try([
        for ancestor_key in local.servers_input_ancestors[server_key] : local.servers_input[ancestor_key].networking.public_address
        if local.servers_input[ancestor_key].networking.public_address != ""
      ][0], null)

      public_ipv4 = try([
        for ancestor_key in local.servers_input_ancestors[server_key] : local.servers_input[ancestor_key].networking.public_ipv4
        if can(cidrhost(local.servers_input[ancestor_key].networking.public_ipv4, 0))
      ][0], null)

      public_ipv6 = try([
        for ancestor_key in local.servers_input_ancestors[server_key] : local.servers_input[ancestor_key].networking.public_ipv6
        if can(cidrhost("${local.servers_input[ancestor_key].networking.public_ipv6}/128", 0))
      ][0], null)
    }
  }

  # Desired server model: YAML plus defaults plus deterministic computed fields.
  # This layer is safe for references that should not depend on generated secrets.
  servers_model_desired = {
    for server_key, server in local.servers_input : server_key => merge(
      server,
      local.servers_model_computed[server_key],
      {
        fqdn_external = "${local.servers_model_computed[server_key].fqdn}.${local.defaults.domains.external}"
        fqdn_internal = "${local.servers_model_computed[server_key].fqdn}.${local.defaults.domains.internal}"
        key           = server_key
        slug          = server_key
      }
    )
  }

  # Runtime server model: provider-backed values and generated secrets that are
  # intentionally kept out of the desired model to make dependencies visible.
  servers_model_runtime = {
    for server_key, server in local.servers_input : server_key => merge(
      {
        age_public_key           = age_secret_key.server[server_key].public_key
        age_secret_key_sensitive = age_secret_key.server[server_key].secret_key
        cloudflare_account_id    = data.cloudflare_account.default.id
        private_address          = try(local.unifi_clients[server_key].local_dns_record, null)
        private_ipv4             = try(local.unifi_clients[server_key].fixed_ip, null)
        ssh_keys                 = data.github_user.default.ssh_keys
        tailscale_device_id      = try(local.tailscale_device_addresses[server_key].id, null)
        tailscale_ipv4           = try(local.tailscale_device_addresses[server_key].ipv4, null)
        tailscale_ipv6           = try(local.tailscale_device_addresses[server_key].ipv6, null)
      },
      server.features.b2 ? {
        b2_application_key_id        = b2_application_key.server[server_key].application_key_id
        b2_application_key_sensitive = b2_application_key.server[server_key].application_key
        b2_bucket_name               = b2_bucket.server[server_key].bucket_name
        b2_endpoint                  = local.b2_endpoint
      } : {},
      server.features.cloudflare_acme_token ? {
        cloudflare_acme_token_sensitive = cloudflare_account_token.server_acme[server_key].value
      } : {},
      server.features.cloudflare_zero_trust_tunnel ? {
        cloudflare_tunnel_id                   = module.cloudflare_tunnel[server_key].tunnel_id
        cloudflare_tunnel_read_token_sensitive = module.cloudflare_tunnel[server_key].tunnel_read_token
        cloudflare_tunnel_token_sensitive      = module.cloudflare_tunnel[server_key].tunnel_token
      } : {},
      server.features.password ? {
        password_hash_sensitive = bcrypt_hash.server[server_key].id
        password_sensitive      = sensitive(try(local.onepassword_server_existing_fields[server_key].password, random_password.server[server_key].result))
      } : {},
      server.features.pushover ? {
        pushover_application_token_sensitive = var.pushover_application_token
        pushover_user_key_sensitive          = var.pushover_user_key
      } : {},
      server.features.resend ? {
        resend_api_key_sensitive = jsondecode(restapi_object.resend_api_key_server[server_key].create_response).token
      } : {},
      server.features.tailscale ? {
        tailscale_auth_key_sensitive = tailscale_tailnet_key.server[server_key].key
      } : {}
    )
  }
}
