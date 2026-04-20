locals {
  # Merge schema defaults into each server file before deriving inherited fields.
  _servers_input_source = {
    for k, v in {
      for filepath in fileset(path.module, "data/servers/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => provider::deepmerge::mergo(local.defaults_server, v)
  }

  # Inheritance is intentionally bounded to self, parent, and grandparent; the
  # validation below fails if data tries to exceed that model.
  _servers_prepare_ancestors = {
    for k, v in local._servers_input_source : k => compact([
      k,
      v.parent,
      try(local._servers_input_source[v.parent].parent, ""),
    ])
  }

  # Parent context keeps inherited description logic readable without adding
  # broader parent inheritance.
  _servers_prepare_parent_context = {
    for k, v in local._servers_input_source : k => {
      region_matches = try(v.identity.region == local._servers_input_source[v.parent].identity.name, false)
      title          = try(local._servers_input_source[v.parent].identity.title, v.parent)
    }
  }

  # Non-provider derived fields used by DNS, templates, Bitwarden, and inventory.
  _servers_refine_computed = {
    for k, v in local._servers_input_source : k => {
      fqdn = length(split("-", k)) == 1 ? k : "${v.identity.name}.${v.identity.region}"
      slug = k

      description = (
        v.parent == "" ? v.identity.title :
        local._servers_prepare_parent_context[k].region_matches ? "${v.identity.title} (${upper(v.identity.region)})" :
        "${local._servers_prepare_parent_context[k].title} ${v.identity.title} (${upper(v.identity.region)})"
      )

      # Public addresses inherit from self, then parent, then grandparent; the
      # first non-empty valid value wins.
      public_address = try([
        for a in local._servers_prepare_ancestors[k] : local._servers_input_source[a].networking.public_address
        if local._servers_input_source[a].networking.public_address != ""
      ][0], null)

      public_ipv4 = try([
        for a in local._servers_prepare_ancestors[k] : local._servers_input_source[a].networking.public_ipv4
        if can(cidrhost(local._servers_input_source[a].networking.public_ipv4, 0))
      ][0], null)

      public_ipv6 = try([
        for a in local._servers_prepare_ancestors[k] : local._servers_input_source[a].networking.public_ipv6
        if can(cidrhost("${local._servers_input_source[a].networking.public_ipv6}/128", 0))
      ][0], null)
    }
  }

  # Desired server model: YAML plus defaults plus deterministic computed fields.
  # This layer is safe for references that should not depend on generated secrets.
  servers_model_desired = {
    for k, v in local._servers_input_source : k => merge(
      v,
      local._servers_refine_computed[k],
      {
        fqdn_external = "${local._servers_refine_computed[k].fqdn}.${local.defaults.domains.external}"
        fqdn_internal = "${local._servers_refine_computed[k].fqdn}.${local.defaults.domains.internal}"
      }
    )
  }

  # Runtime server model: provider-backed values and generated secrets that are
  # intentionally kept out of the desired model to make dependencies visible.
  servers_model_runtime = {
    for k, v in local._servers_input_source : k => merge(
      {
        age_public_key           = age_secret_key.server[k].public_key
        age_secret_key_sensitive = age_secret_key.server[k].secret_key
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

  # Feature maps use YAML/default data, not provider-enriched servers, to avoid
  # making feature resources depend on the resources they create.
  servers_output_by_feature = {
    for feature in keys(local.defaults_server.features) : feature => {
      for k, v in local._servers_input_source : k => v
      if v.features[feature]
    }
  }

  # Private generated server view used where runtime fields are required.
  servers_output_private = {
    for k, v in local.servers_model_desired : k => merge(
      v,
      local.servers_model_runtime[k]
    )
  }

  # Public server maps are safe for cross-service inventory templates.
  servers_output_public = {
    for k, v in local.servers_model_desired : k => {
      description   = v.description
      fqdn_external = v.fqdn_external
      fqdn_internal = v.fqdn_internal
      identity      = v.identity
      platform      = v.platform
      slug          = v.slug
      type          = v.type
    }
  }
}

resource "random_password" "server" {
  for_each = local.servers_output_by_feature.password

  length = 32
}

resource "terraform_data" "servers_validation" {
  input = keys(local._servers_input_source)

  lifecycle {
    # Incus remotes are configured from parent server management addresses.
    precondition {
      condition     = length([for k, v in local._servers_input_source : k if v.platform == "incus" && v.type == "vm" && (v.parent == "" || try(local._servers_input_source[v.parent].platform != "incus" || local._servers_input_source[v.parent].type != "server" || local._servers_input_source[v.parent].networking.management_address == "", true))]) == 0
      error_message = "Incus VMs must reference an Incus server parent with networking.management_address set: ${join(", ", [for k, v in local._servers_input_source : k if v.platform == "incus" && v.type == "vm" && (v.parent == "" || try(local._servers_input_source[v.parent].platform != "incus" || local._servers_input_source[v.parent].type != "server" || local._servers_input_source[v.parent].networking.management_address == "", true))])}"
    }

    precondition {
      condition     = length([for k, v in local._servers_input_source : "${k} -> ${v.parent}" if v.parent != "" && !contains(keys(local._servers_input_source), v.parent)]) == 0
      error_message = "Invalid parent references found in servers configuration: ${join(", ", [for k, v in local._servers_input_source : "${k} -> ${v.parent}" if v.parent != "" && !contains(keys(local._servers_input_source), v.parent)])}"
    }

    # OCI resources in this stack only model VM instances, not bare metal or
    # appliance/server abstractions.
    precondition {
      condition     = length([for k, v in local._servers_input_source : k if v.platform == "oci" && v.type != "vm"]) == 0
      error_message = "OCI servers must be type vm: ${join(", ", [for k, v in local._servers_input_source : k if v.platform == "oci" && v.type != "vm"])}"
    }

    # OpenTofu locals are not generally recursive; keep the supported inheritance
    # depth explicit so addressing behavior remains predictable.
    precondition {
      condition = length([
        for k, v in local._servers_input_source : k
        if v.parent != "" && try(local._servers_input_source[local._servers_input_source[v.parent].parent].parent != "", false)
      ]) == 0
      error_message = "Server parent inheritance supports at most two parent levels: ${join(", ", [
        for k, v in local._servers_input_source : k
        if v.parent != "" && try(local._servers_input_source[local._servers_input_source[v.parent].parent].parent != "", false)
      ])}"
    }

    # Pushover values are pass-through variables, so provider validation will not
    # catch missing credentials for enabled servers.
    precondition {
      condition = length([
        for k, v in local._servers_input_source : k
        if v.features.pushover && (nonsensitive(var.pushover_application_token) == "" || nonsensitive(var.pushover_user_key) == "")
      ]) == 0
      error_message = "Servers with features.pushover enabled require pushover_application_token and pushover_user_key: ${join(", ", [
        for k, v in local._servers_input_source : k
        if v.features.pushover && (nonsensitive(var.pushover_application_token) == "" || nonsensitive(var.pushover_user_key) == "")
      ])}"
    }

    # Catch short cycles before inherited address lookup hides the root cause.
    precondition {
      condition = length([
        for k, v in local._servers_input_source : k
        if v.parent != "" && (
          try(local._servers_input_source[v.parent].parent == k, false) ||
          try(local._servers_input_source[local._servers_input_source[v.parent].parent].parent == k, false)
        )
      ]) == 0
      error_message = "Server parent references contain a cycle within the supported parent depth: ${join(", ", [
        for k, v in local._servers_input_source : k
        if v.parent != "" && (
          try(local._servers_input_source[v.parent].parent == k, false) ||
          try(local._servers_input_source[local._servers_input_source[v.parent].parent].parent == k, false)
        )
      ])}"
    }

    precondition {
      condition     = length([for k, v in local._servers_input_source : k if v.parent == k]) == 0
      error_message = "Servers cannot set themselves as their own parent: ${join(", ", [for k, v in local._servers_input_source : k if v.parent == k])}"
    }
  }
}

output "servers" {
  description = "Server configurations"
  sensitive   = true

  # Output view removes empty fields but remains sensitive because it includes secrets.
  value = {
    for k, v in local.servers_output_private : k => {
      for kk, vv in v : kk => vv
      if vv != null && vv != "" && vv != false
    }
  }
}
