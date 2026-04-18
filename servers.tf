locals {
  _servers = {
    for k, v in {
      for filepath in fileset(path.module, "data/servers/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => provider::deepmerge::mergo(local.server_defaults, v)
  }

  _servers_ancestors = {
    for k, v in local._servers : k => compact([
      k,
      v.parent,
      try(local._servers[v.parent].parent, ""),
    ])
  }

  _servers_computed = {
    for k, v in local._servers : k => {
      description = v.parent == "" ? v.identity.title : (try(v.identity.region == local._servers[v.parent].identity.name, false) ? "${v.identity.title} (${upper(v.identity.region)})" : "${try(local._servers[v.parent].identity.title, v.parent)} ${v.identity.title} (${upper(v.identity.region)})")
      fqdn        = length(split("-", k)) == 1 ? k : "${v.identity.name}.${v.identity.region}"
      slug        = k

      public_address = try([
        for a in local._servers_ancestors[k] : local._servers[a].networking.public_address
        if local._servers[a].networking.public_address != ""
      ][0], null)

      public_ipv4 = try([
        for a in local._servers_ancestors[k] : local._servers[a].networking.public_ipv4
        if can(cidrhost(local._servers[a].networking.public_ipv4, 0))
      ][0], null)

      public_ipv6 = try([
        for a in local._servers_ancestors[k] : local._servers[a].networking.public_ipv6
        if can(cidrhost("${local._servers[a].networking.public_ipv6}/128", 0))
      ][0], null)
    }
  }

  servers = {
    for k, v in local._servers : k => merge(
      v,
      local._servers_computed[k],
      {
        age_public_key           = age_secret_key.server[k].public_key
        age_secret_key_sensitive = age_secret_key.server[k].secret_key
        fqdn_external            = "${local._servers_computed[k].fqdn}.${local.defaults.domains.external}"
        fqdn_internal            = "${local._servers_computed[k].fqdn}.${local.defaults.domains.internal}"
        password_hash_sensitive  = v.features.password ? bcrypt_hash.server[k].id : null
        password_sensitive       = v.features.password ? random_password.server[k].result : null
        private_address          = try(local.unifi_clients[k].local_dns_record, null)
        private_ipv4             = try(local.unifi_clients[k].fixed_ip, null)
        ssh_keys                 = data.github_user.default.ssh_keys
        tailscale_ipv4           = try(local.tailscale_device_addresses[k].ipv4, null)
        tailscale_ipv6           = try(local.tailscale_device_addresses[k].ipv6, null)
      },
      v.features.b2 ? {
        b2_application_key_id        = b2_application_key.server[k].application_key_id
        b2_application_key_sensitive = b2_application_key.server[k].application_key
        b2_bucket_name               = b2_bucket.server[k].bucket_name
        b2_endpoint                  = replace(data.b2_account_info.default.s3_api_url, "https://", "")
      } : {},
      v.features.cloudflare_acme_token ? {
        cloudflare_acme_account_id      = data.cloudflare_account.default.id
        cloudflare_acme_token_sensitive = cloudflare_account_token.server_acme[k].value
      } : {},
      v.features.cloudflare_zero_trust_tunnel ? {
        cloudflare_zero_trust_tunnel_token_sensitive = data.cloudflare_zero_trust_tunnel_cloudflared_token.server[k].token
      } : {},
      v.features.pushover ? {
        pushover_application_token_sensitive = var.pushover_application_token
        pushover_user_key_sensitive          = var.pushover_user_key
      } : {},
      v.features.resend ? {
        resend_api_key_sensitive = jsondecode(restapi_object.resend_api_key_server[k].create_response).token
      } : {},
      v.features.tailscale ? {
        tailscale_auth_key_sensitive = tailscale_tailnet_key.server[k].key
      } : {}
    )
  }

  servers_by_feature = {
    for feature in keys(local.server_defaults.features) : feature => {
      for k, v in local._servers : k => v
      if v.features[feature]
    }
  }

  servers_filtered = {
    for k, v in local.servers : k => {
      for kk, vv in v : kk => vv
      if vv != null && vv != "" && vv != false
    }
  }
}

resource "random_password" "server" {
  for_each = local.servers_by_feature.password

  length = 32
}

resource "terraform_data" "servers_validation" {
  input = keys(local._servers)

  lifecycle {
    precondition {
      condition     = length([for k, v in local._servers : "${k} -> ${v.parent}" if v.parent != "" && !contains(keys(local._servers), v.parent)]) == 0
      error_message = "Invalid parent references found in servers configuration: ${join(", ", [for k, v in local._servers : "${k} -> ${v.parent}" if v.parent != "" && !contains(keys(local._servers), v.parent)])}"
    }

    precondition {
      condition     = length([for k, v in local._servers : k if v.parent == k]) == 0
      error_message = "Servers cannot set themselves as their own parent: ${join(", ", [for k, v in local._servers : k if v.parent == k])}"
    }
  }
}

output "servers" {
  description = "Server configurations"
  sensitive   = true
  value       = local.servers_filtered
}
