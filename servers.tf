data "external" "onepassword_servers" {
  program = [
    "${path.module}/scripts/onepassword-vault-read.sh",
    var.onepassword_servers_vault
  ]

  query = {
    connect_host  = var.onepassword_connect_host
    connect_token = var.onepassword_connect_token
  }
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
        password_hash = htpasswd_password.server[k].sha512
        resources     = local.servers_resources[k]
        ssh_keys      = data.github_user.default.ssh_keys
        output = merge(
          # Base resources
          {
            acme_dns_password_sensitive = shell_sensitive_script.acme_dns_server[k].output.password
            acme_dns_subdomain          = shell_sensitive_script.acme_dns_server[k].output.subdomain
            acme_dns_username           = shell_sensitive_script.acme_dns_server[k].output.username
            fqdn_external               = "${v.fqdn}.${var.defaults.domain_external}"
            fqdn_internal               = "${v.fqdn}.${var.defaults.domain_internal}"
            private_ipv4                = v.input.private_ipv4

            public_address = try(
              coalesce(
                v.input.public_address,
                try(local._servers[v.input.parent].input.public_address, null)
              ),
              null
            )

            public_ipv4 = try(
              coalesce(
                v.input.public_ipv4,
                try(local._servers[v.input.parent].input.public_ipv4, null)
              ),
              null
            )

            public_ipv6 = try(
              coalesce(
                v.input.public_ipv6,
                try(local._servers[v.input.parent].input.public_ipv6, null)
              ),
              null
            )

            tailscale_ipv4 = try(
              local.tailscale_device_addresses[v.platform == "router" ? v.name : "${v.region}-${v.name}"].ipv4,
              null
            )

            tailscale_ipv6 = try(
              local.tailscale_device_addresses[v.platform == "router" ? v.name : "${v.region}-${v.name}"].ipv6,
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
          } : {},

          # Cloudflared resources
          local.servers_resources[k].cloudflared ? {
            cloudflared_tunnel_token_sensitive = data.cloudflare_zero_trust_tunnel_cloudflared_token.server[k].token
          } : {},

          # Docker resources
          local.servers_resources[k].docker ? {
            tailscale_caddy_key_sensitive = tailscale_tailnet_key.caddy[k].key
          } : {},

          # Komodo resources
          local.servers_resources[k].komodo ? {
            age_private_key_sensitive = age_secret_key.server[k].secret_key
            age_public_key            = age_secret_key.server[k].public_key
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

  servers_outputs_filtered = {
    for k, v in local.servers : k => {
      for output_key, output_value in v.output : output_key => output_value
      if !can(regex(var.url_field_pattern, output_key))
    }
  }

  servers_resources = {
    for k, v in local._servers : k => {
      for resource in var.server_resources : resource => contains(try(split(",", replace(v.input.resources, " ", "")), []), resource)
    }
  }

  servers_urls = {
    for k, v in local.servers : k => [
      for key in sort(keys(v.output)) : merge(
        {
          href = format(
            "%s%s",
            can(cidrhost("${v.output[key]}/128", 0)) ? "[${v.output[key]}]" : v.output[key],
            v.input.management_port != null ? ":${v.input.management_port}" : ""
          )
          label = key
        },
        key == "fqdn_internal" ? { primary = true } : {}
      )
      if can(regex(var.url_field_pattern, key)) && v.output[key] != null
    ]
  }
}

output "servers" {
  value     = keys(local._servers)
  sensitive = false
}

resource "shell_sensitive_script" "onepassword_server_sync" {
  for_each = local._servers

  environment = {
    CONNECT_HOST  = var.onepassword_connect_host
    CONNECT_TOKEN = var.onepassword_connect_token
    ID            = each.value.id
    OUTPUTS_JSON  = jsonencode(local.servers_outputs_filtered[each.key])
    URLS_JSON     = jsonencode(local.servers_urls[each.key])
    VAULT         = var.onepassword_servers_vault
  }

  lifecycle_commands {
    create = "${path.module}/scripts/onepassword-server-write.sh"
    delete = "true"
  }

  triggers = {
    outputs_hash      = sha256(jsonencode(local.servers_outputs_filtered[each.key]))
    script_read_hash  = filemd5("${path.module}/scripts/onepassword-vault-read.sh")
    script_write_hash = filemd5("${path.module}/scripts/onepassword-server-write.sh")
    urls_hash         = sha256(jsonencode(local.servers_urls[each.key]))
  }
}
