data "external" "onepassword_servers" {
  program = [
    "${path.module}/scripts/onepassword-vault-read.sh",
    var.onepassword_servers_vault
  ]
}

locals {
  _servers = {
    for k, v in data.external.onepassword_servers.result : k => merge(
      jsondecode(v),
      {
        fqdn     = length(split("-", k)) > 2 ? "${join("-", slice(split("-", k), 2, length(split("-", k))))}.${split("-", k)[1]}" : split("-", k)[1]
        name     = length(split("-", k)) > 2 ? join("-", slice(split("-", k), 2, length(split("-", k)))) : split("-", k)[1]
        platform = split("-", k)[0]
        region   = split("-", k)[1]
        input = merge(
          var.server_defaults,
          jsondecode(v).input
        ),
      }
    )
  }

  servers = {
    for k, v in local._servers : k => merge(
      v,
      {
        output = merge(
          # Base computed values
          {
            acme_dns_password_sensitive = nonsensitive(shell_sensitive_script.acme_dns_server[k].output.password)
            acme_dns_subdomain          = nonsensitive(shell_sensitive_script.acme_dns_server[k].output.subdomain)
            acme_dns_username           = nonsensitive(shell_sensitive_script.acme_dns_server[k].output.username)
            age_private_key_sensitive   = nonsensitive(age_secret_key.server[k].secret_key)
            age_public_key              = nonsensitive(age_secret_key.server[k].public_key)
            fqdn_external               = "${v.fqdn}.${var.defaults.domain_external}"
            fqdn_internal               = "${v.fqdn}.${var.defaults.domain_internal}"
            private_ipv4                = v.input.private_ipv4.value

            public_address = try(
              coalesce(
                v.input.public_address.value,
                try(local._servers[v.input.parent.value].input.public_address.value, null)
              ),
              null
            )

            public_ipv4 = try(
              coalesce(
                v.input.public_ipv4.value,
                try(local._servers[v.input.parent.value].input.public_ipv4.value, null)
              ),
              null
            )

            public_ipv6 = try(
              coalesce(
                v.input.public_ipv6.value,
                try(local._servers[v.input.parent.value].input.public_ipv6.value, null)
              ),
              null
            )

            tailscale_ipv4 = try(
              local.tailscale_device_addresses["${v.region}-${v.name}"].ipv4,
              null
            )

            tailscale_ipv6 = try(
              local.tailscale_device_addresses["${v.region}-${v.name}"].ipv6,
              null
            )
          },

          # Backblaze B2 resources
          local.servers_resources[k].b2 ? {
            b2_application_key_sensitive = b2_application_key.server[k].application_key
            b2_application_key_id        = b2_application_key.server[k].application_key_id
            b2_bucket_name               = b2_bucket.server[k].bucket_name
            b2_endpoint                  = replace(data.b2_account_info.default.s3_api_url, "https://", "")
          } : {},

          # Cloudflare resources
          local.servers_resources[k].cloudflare ? {
            cloudflare_account_token_sensitive = cloudflare_account_token.server[k].value
            cloudflare_tunnel_token_sensitive  = data.cloudflare_zero_trust_tunnel_cloudflared_token.server[k].token
          } : {},

          # Docker resources
          local.servers_resources[k].docker ? {
            tailscale_caddy_key_sensitive = tailscale_tailnet_key.caddy[k].key
          } : {},

          # Resend resources
          local.servers_resources[k].resend ? {
            resend_api_key_sensitive = jsondecode(restapi_object.resend_api_key_server[k].create_response).token
          } : {},

          # Tailscale resources
          local.servers_resources[k].tailscale ? {
            tailscale_auth_key_sensitive = tailscale_tailnet_key.server[k].key
          } : {}
        )
      }
    )
  }

  servers_resources = {
    for k, v in local._servers : k => {
      for resource in var.server_resources : resource => contains(try(split(",", v.input.resources.value), []), resource)
    }
  }

  servers_urls = {
    for k, v in local.servers : k => [
      for url in [
        v.output.fqdn_external,
        v.output.fqdn_internal,
        v.output.private_ipv4,
        v.output.public_address,
        v.output.public_ipv4,
        v.output.public_ipv6,
        v.output.tailscale_ipv4,
        v.output.tailscale_ipv6
      ] : "${url}${v.input.management_port.value != null ? ":${v.input.management_port.value}" : ""}"
      if url != null
    ]
  }
}

output "servers" {
  value     = keys(local._servers)
  sensitive = false
}

resource "shell_sensitive_script" "onepassword_server_sync" {
  for_each = local.servers

  environment = {
    ID           = each.value.id
    INPUTS_JSON  = jsonencode(each.value.input)
    NOTES        = each.value.notes
    OUTPUTS_JSON = jsonencode(each.value.output)
    PASSWORD     = each.value.password
    URLS_JSON    = jsonencode(local.servers_urls[each.key])
    USERNAME     = each.value.username
    VAULT        = var.onepassword_servers_vault
  }

  lifecycle_commands {
    create = "${path.module}/scripts/onepassword-server-write.sh"
    delete = "true"
    read   = "echo {}"
  }

  triggers = {
    inputs_hash   = sha256(jsonencode(each.value.input))
    notes_hash    = sha256(each.value.notes)
    outputs_hash  = sha256(jsonencode(each.value.output))
    password_hash = sha256(each.value.password)
    urls_hash     = sha256(jsonencode(local.servers_urls[each.key]))
    username_hash = sha256(each.value.username)

    script_read_hash  = filemd5("${path.module}/scripts/onepassword-vault-read.sh")
    script_write_hash = filemd5("${path.module}/scripts/onepassword-server-write.sh")
  }
}
