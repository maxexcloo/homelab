locals {
  _servers = {
    for k, v in {
      for filepath in fileset(path.module, "data/servers/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => merge(var.server_defaults, v)
  }

  _servers_computed = {
    for k, v in local._servers : k => {
      description = v.parent == "" || v.parent == null ? v.description : "${local._servers[v.parent].description} ${v.description} (${upper(v.region)})"
      fqdn        = length(split("-", k)) == 1 ? k : "${v.name}.${v.region}"

      public_address = try(
        v.public_address != "" ? v.public_address : null,
        v.parent != "" ? local._servers[v.parent].public_address : null,
        v.parent != "" && local._servers[v.parent].parent != "" ? local._servers[local._servers[v.parent].parent].public_address : null,
        null
      )
      public_ipv4 = try(
        can(cidrhost(v.public_ipv4, 0)) ? v.public_ipv4 : null,
        v.parent != "" && can(cidrhost(local._servers[v.parent].public_ipv4, 0)) ? local._servers[v.parent].public_ipv4 : null,
        null
      )
      public_ipv6 = try(
        can(cidrhost("${v.public_ipv6}/128", 0)) ? v.public_ipv6 : null,
        v.parent != "" && can(cidrhost("${local._servers[v.parent].public_ipv6}/128", 0)) ? local._servers[v.parent].public_ipv6 : null,
        null
      )
    }
  }

  servers = {
    for k, v in local._servers : k => merge(
      v,
      local._servers_computed[k],
      {
        fqdn_external   = "${local._servers_computed[k].fqdn}.${local.defaults.domain_external}"
        fqdn_internal   = "${local._servers_computed[k].fqdn}.${local.defaults.domain_internal}"
        password_hash   = v.enable_password ? htpasswd_password.server[k].sha512 : ""
        private_address = try(local.unifi_clients[k].local_dns_record, null)
        private_ipv4    = try(local.unifi_clients[k].fixed_ip, null)
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
        cloudflare_acme_token_sensitive = cloudflare_account_token.server_acme[k].value
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
  for_each = {
    for k, v in local._servers : k => v
    if v.enable_password
  }

  length = 32
}

output "servers" {
  value     = keys(local._servers)
  sensitive = false
}
