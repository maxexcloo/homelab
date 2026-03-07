locals {
  _servers = {
    for k, v in {
      for filepath in fileset(path.module, "data/servers/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : k => merge(var.server_defaults, v)
  }

  servers = {
    for k, v in local._servers : k => merge(
      v,
      {
        fqdn          = local._server_fqdn[k]
        fqdn_external = "${local._server_fqdn[k]}.${local.defaults.domain_external}"
        fqdn_internal = "${local._server_fqdn[k]}.${local.defaults.domain_internal}"
        password_hash = try(htpasswd_password.server[k].sha512, "")
        ssh_keys      = data.github_user.default.ssh_keys

        private_address = try(local.unifi_clients[k].local_dns_record, null)
        private_ipv4    = try(local.unifi_clients[k].fixed_ip, null)

        public_address = try(coalesce(v.public_address, try(local._servers[v.parent].public_address, null)), null)
        public_ipv4    = try(coalesce(v.public_ipv4, try(local._servers[v.parent].public_ipv4, null)), null)
        public_ipv6    = try(coalesce(v.public_ipv6, try(local._servers[v.parent].public_ipv6, null)), null)
      },
      v.enable_b2 ? {
        b2_application_key_id        = b2_application_key.server[k].application_key_id
        b2_application_key_sensitive = b2_application_key.server[k].application_key
        b2_bucket_name               = b2_bucket.server[k].bucket_name
        b2_endpoint                  = replace(data.b2_account_info.default.s3_api_url, "https://", "")
      } : {},
      v.enable_cloudflare_acme_token ? {
        cloudflare_account_token_sensitive = cloudflare_account_token.server[k].value
      } : {},
      v.enable_cloudflared_tunnel ? {
        cloudflared_tunnel_token_sensitive = data.cloudflare_zero_trust_tunnel_cloudflared_token.server[k].token
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

  _server_fqdn = {
    for k, v in local._servers : k => (
      length(split("-", k)) == 1 ?
      k :
      "${join("-", slice(split("-", k), 1, length(split("-", k))))}.${split("-", k)[0]}"
    )
  }
}

resource "random_password" "server" {
  for_each = local._servers
  length   = 32
  special  = true
}

output "servers" {
  value     = keys(local._servers)
  sensitive = false
}
