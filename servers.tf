locals {
  _servers = {
    for k, v in {
      for filepath in fileset(path.module, "data/servers/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => merge(var.server_defaults, v)
  }

  _servers_resolve_parent_value = {
    for k, v in local._servers : k => {
      public_address = try(
        coalesce(
          v.public_address,
          try(local._servers[v.parent].public_address, null),
          try(local._servers[local._servers[v.parent].parent].public_address, null),
          try(local._servers[local._servers[local._servers[v.parent].parent].parent].public_address, null),
          try(local._servers[local._servers[local._servers[local._servers[v.parent].parent].parent].parent].public_address, null),
          try(local._servers[local._servers[local._servers[local._servers[local._servers[v.parent].parent].parent].parent].parent].public_address, null)
        ),
        null
      )
      public_ipv4 = try(
        coalesce(
          v.public_ipv4,
          try(local._servers[v.parent].public_ipv4, null),
          try(local._servers[local._servers[v.parent].parent].public_ipv4, null),
          try(local._servers[local._servers[local._servers[v.parent].parent].parent].public_ipv4, null),
          try(local._servers[local._servers[local._servers[local._servers[v.parent].parent].parent].parent].public_ipv4, null),
          try(local._servers[local._servers[local._servers[local._servers[local._servers[v.parent].parent].parent].parent].parent].public_ipv4, null)
        ),
        null
      )
      public_ipv6 = try(
        coalesce(
          v.public_ipv6,
          try(local._servers[v.parent].public_ipv6, null),
          try(local._servers[local._servers[v.parent].parent].public_ipv6, null),
          try(local._servers[local._servers[local._servers[v.parent].parent].parent].public_ipv6, null),
          try(local._servers[local._servers[local._servers[local._servers[v.parent].parent].parent].parent].public_ipv6, null),
          try(local._servers[local._servers[local._servers[local._servers[local._servers[v.parent].parent].parent].parent].parent].public_ipv6, null)
        ),
        null
      )
    }
  }

  # Build FQDN as name.region (not full hierarchy)
  # au -> au
  # au-pie -> pie.au
  # au-pie-truenas -> truenas.au
  _fqdn_from_id = {
    for k, v in local._servers : k => (
      length(split("-", k)) == 1 ?
      k :
      "${v.name}.${v.region}"
    )
  }

  servers = {
    for k, v in local._servers : k => merge(
      v,
      {
        fqdn            = local._fqdn_from_id[k]
        fqdn_external   = "${local._fqdn_from_id[k]}.${local.defaults.domain_external}"
        fqdn_internal   = "${local._fqdn_from_id[k]}.${local.defaults.domain_internal}"
        password_hash   = v.enable_password ? htpasswd_password.server[k].sha512 : ""
        private_address = try(local.unifi_clients[k].local_dns_record, null)
        private_ipv4    = try(local.unifi_clients[k].fixed_ip, null)
        public_address  = local._servers_resolve_parent_value[k].public_address
        public_ipv4     = local._servers_resolve_parent_value[k].public_ipv4
        public_ipv6     = local._servers_resolve_parent_value[k].public_ipv6
        ssh_keys        = data.github_user.default.ssh_keys
      },
      v.enable_b2 ? {
        b2_application_key_id        = b2_application_key.server[k].application_key_id
        b2_application_key_sensitive = b2_application_key.server[k].application_key
        b2_bucket_name               = b2_bucket.server[k].bucket_name
        b2_endpoint                  = replace(data.b2_account_info.default.s3_api_url, "https://", "")
      } : {},
      v.enable_cloudflare_acme_token ? {
        cloudflare_acme_account_id      = data.cloudflare_accounts.default.result[0].id
        cloudflare_acme_token_sensitive = cloudflare_account_token.server[k].value
      } : {},
      v.enable_cloudflare_zero_trust_tunnel ? {
        cloudflare_zero_trust_tunnel_token_sensitive = data.cloudflare_zero_trust_tunnel_cloudflared_token.server[k].token
      } : {},
      v.enable_resend ? {
        resend_api_key_sensitive = jsondecode(restapi_object.resend_api_key_server[k].create_response).token
      } : {},
      v.enable_tailscale ? {
        tailscale_auth_key_sensitive = tailscale_tailnet_key.server[k].key
        tailscale_ipv4               = try(local.tailscale_device_addresses[k].ipv4, null)
        tailscale_ipv6               = try(local.tailscale_device_addresses[k].ipv6, null)
      } : {}
    )
  }

}

resource "random_password" "server" {
  for_each = local._servers

  length = 32
}

output "servers" {
  value     = keys(local._servers)
  sensitive = false
}
