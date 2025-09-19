locals {
  # Complete homelab data with structured input/output sections
  homelab = {
    for k, v in local.homelab_discovered : k => merge(
      v,
      {
        url = "${v.fqdn}.${var.domain_internal}${v.input.management_port != null ? ":${v.input.management_port}" : "")}"

        input = v.input
        output = merge(
          # Computed values
          {
            acme_dns_password  = shell_script.acme_dns_homelab[k].output.password
            acme_dns_subdomain = shell_script.acme_dns_homelab[k].output.subdomain
            acme_dns_username  = shell_script.acme_dns_homelab[k].output.username
            age_private_key    = resource.shell_script.age_homelab[k].output.private_key
            age_public_key     = resource.shell_script.age_homelab[k].output.public_key
            fqdn_external      = "${v.fqdn}.${var.domain_external}"
            fqdn_internal      = "${v.fqdn}.${var.domain_internal}"

            public_address = try(
              coalesce(
                v.input.public_address,
                try(local.homelab_discovered[v.input.parent].input.public_address, null)
              ),
              null
            )

            public_ipv4 = try(
              coalesce(
                v.input.public_ipv4,
                try(local.homelab_discovered[v.input.parent].input.public_ipv4, null)
              ),
              null
            )

            public_ipv6 = try(
              coalesce(
                v.input.public_ipv6,
                try(local.homelab_discovered[v.input.parent].input.public_ipv6, null)
              ),
              null
            )

            tailscale_ipv4 = try(
              local.tailscale_device_addresses[v.slug].ipv4,
              null
            )

            tailscale_ipv6 = try(
              local.tailscale_device_addresses[v.slug].ipv6,
              null
            )
          },

          # Backblaze B2
          local.homelab_resources[k].b2 ? {
            b2_application_key    = b2_application_key.homelab[k].application_key
            b2_application_key_id = b2_application_key.homelab[k].application_key_id
            b2_bucket_name        = b2_bucket.homelab[k].bucket_name
            b2_endpoint           = replace(data.b2_account_info.default.s3_api_url, "https://", "")
          } : {},

          # Cloudflare
          local.homelab_resources[k].cloudflare ? {
            cloudflare_account_token = cloudflare_account_token.homelab[k].value
            cloudflare_tunnel_token  = data.cloudflare_zero_trust_tunnel_cloudflared_token.homelab[k].token
          } : {},

          # Docker
          local.homelab_resources[k].docker ? {
            tailscale_caddy_key = tailscale_tailnet_key.caddy[k].key
          } : {},

          # Resend
          local.homelab_resources[k].resend ? {
            resend_api_key = jsondecode(restapi_object.resend_api_key_homelab[k].create_response).token
          } : {},

          # Tailscale
          local.homelab_resources[k].tailscale ? {
            tailscale_auth_key = tailscale_tailnet_key.homelab[k].key
          } : {}
        )
      }
    )
  }

  # Determine which resources to create for each homelab item
  homelab_resources = {
    for k, v in local.homelab_discovered : k => {
      for resource in var.resources_homelab : resource => contains(try(split(",", replace(v.input.resources, " ", "")), []), resource)
    }
  }

  # Parse tags from input field
  homelab_tags = {
    for k, v in local.homelab_discovered : k => try(split(",", replace(v.input.tags, " ", "")), [])
  }
}
