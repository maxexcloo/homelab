locals {
  # Merge schema defaults into each server file before deriving inherited fields.
  _servers = {
    for k, v in {
      for filepath in fileset(path.module, "data/servers/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => provider::deepmerge::mergo(local.server_defaults, v)
  }

  # Inheritance is intentionally bounded to self, parent, and grandparent; the
  # validation below fails if data tries to exceed that model.
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

  # Filter maps use the merged data, not provider-enriched servers, to avoid
  # accidentally making feature resources depend on the resources they create.
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

  # Public server maps are safe for cross-service inventory templates.
  servers_public = {
    for k, v in local.servers : k => {
      description   = v.description
      fqdn_external = v.fqdn_external
      fqdn_internal = v.fqdn_internal
      platform      = v.platform
      slug          = v.slug
      type          = v.type

      identity = v.identity
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
    # Incus remotes are configured from parent server management addresses.
    precondition {
      condition     = length([for k, v in local._servers : k if v.platform == "incus" && v.type == "vm" && (v.parent == "" || try(local._servers[v.parent].platform != "incus" || local._servers[v.parent].type != "server" || local._servers[v.parent].networking.management_address == "", true))]) == 0
      error_message = "Incus VMs must reference an Incus server parent with networking.management_address set: ${join(", ", [for k, v in local._servers : k if v.platform == "incus" && v.type == "vm" && (v.parent == "" || try(local._servers[v.parent].platform != "incus" || local._servers[v.parent].type != "server" || local._servers[v.parent].networking.management_address == "", true))])}"
    }

    precondition {
      condition     = length([for k, v in local._servers : "${k} -> ${v.parent}" if v.parent != "" && !contains(keys(local._servers), v.parent)]) == 0
      error_message = "Invalid parent references found in servers configuration: ${join(", ", [for k, v in local._servers : "${k} -> ${v.parent}" if v.parent != "" && !contains(keys(local._servers), v.parent)])}"
    }

    # OCI resources in this stack only model VM instances, not bare metal or
    # appliance/server abstractions.
    precondition {
      condition     = length([for k, v in local._servers : k if v.platform == "oci" && v.type != "vm"]) == 0
      error_message = "OCI servers must be type vm: ${join(", ", [for k, v in local._servers : k if v.platform == "oci" && v.type != "vm"])}"
    }

    # OpenTofu locals are not generally recursive; keep the supported inheritance
    # depth explicit so addressing behavior remains predictable.
    precondition {
      condition = length([
        for k, v in local._servers : k
        if v.parent != "" && try(local._servers[local._servers[v.parent].parent].parent != "", false)
      ]) == 0
      error_message = "Server parent inheritance supports at most two parent levels: ${join(", ", [
        for k, v in local._servers : k
        if v.parent != "" && try(local._servers[local._servers[v.parent].parent].parent != "", false)
      ])}"
    }

    # Pushover values are pass-through variables, so provider validation will not
    # catch missing credentials for enabled servers.
    precondition {
      condition = length([
        for k, v in local._servers : k
        if v.features.pushover && (nonsensitive(var.pushover_application_token) == "" || nonsensitive(var.pushover_user_key) == "")
      ]) == 0
      error_message = "Servers with features.pushover enabled require pushover_application_token and pushover_user_key: ${join(", ", [
        for k, v in local._servers : k
        if v.features.pushover && (nonsensitive(var.pushover_application_token) == "" || nonsensitive(var.pushover_user_key) == "")
      ])}"
    }

    # Catch short cycles before inherited address lookup hides the root cause.
    precondition {
      condition = length([
        for k, v in local._servers : k
        if v.parent != "" && (
          try(local._servers[v.parent].parent == k, false) ||
          try(local._servers[local._servers[v.parent].parent].parent == k, false)
        )
      ]) == 0
      error_message = "Server parent references contain a cycle within the supported parent depth: ${join(", ", [
        for k, v in local._servers : k
        if v.parent != "" && (
          try(local._servers[v.parent].parent == k, false) ||
          try(local._servers[local._servers[v.parent].parent].parent == k, false)
        )
      ])}"
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
