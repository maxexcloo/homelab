locals {
  # Complete homelab data with all fields merged and computed
  homelab = {
    for k, v in local.homelab_discovered : k => merge(
      # Base: Discovery metadata
      v,

      # 1Password fields (flattened from input/output sections)
      local.homelab_fields[k].input,
      local.homelab_fields[k].output,

      # Layer 1: Computed and inherited fields
      {
        # Network inheritance (child inherits from parent router if not set)
        public_address = try(
          coalesce(
            local.homelab_fields[k].input.public_address,
            try(local.homelab_fields[local.homelab_parent[k]].input.public_address, null)
          ),
          null
        )

        public_ipv4 = try(
          coalesce(
            local.homelab_fields[k].input.public_ipv4,
            try(local.homelab_fields[local.homelab_parent[k]].input.public_ipv4, null)
          ),
          null
        )

        public_ipv6 = try(
          coalesce(
            local.homelab_fields[k].input.public_ipv6,
            try(local.homelab_fields[local.homelab_parent[k]].input.public_ipv6, null)
          ),
          null
        )

        # Path defaults based on username
        paths = try(
          coalesce(local.homelab_fields[k].input.paths),
          data.onepassword_item.homelab[k].username == "root" ? "/root" : "/home/${data.onepassword_item.homelab[k].username}"
        )

        # Computed URLs and domains
        fqdn_external = "${v.fqdn}.${var.domain_external}"
        fqdn_internal = "${v.fqdn}.${var.domain_internal}"
        url           = "${v.fqdn}.${var.domain_internal}${try(":${local.homelab_fields[k].input.management_port}", "")}"

        # Parse tags from comma-separated string
        tags = try(split(",", replace(coalesce(local.homelab_fields[k].input.tags, ""), " ", "")), [])

        # Tailscale device IPs (from device lookup)
        tailscale_ipv4 = try(local.tailscale_device_addresses[v.title].ipv4, null)
        tailscale_ipv6 = try(local.tailscale_device_addresses[v.title].ipv6, null)
      },

      # Layer 2: Resource-generated credentials
      # ACME DNS
      {
        acme_dns_password  = shell_script.acme_dns_homelab[k].output.password
        acme_dns_subdomain = shell_script.acme_dns_homelab[k].output.subdomain
        acme_dns_username  = shell_script.acme_dns_homelab[k].output.username
      },

      # Age encryption keys for SOPS
      {
        age_private_key = resource.shell_script.age_homelab[k].output.private_key
        age_public_key  = resource.shell_script.age_homelab[k].output.public_key
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

      # Resend
      local.homelab_resources[k].resend ? {
        resend_api_key = jsondecode(restapi_object.resend_api_key_homelab[k].create_response).token
      } : {},

      # Tailscale
      local.homelab_resources[k].tailscale ? {
        tailscale_auth_key = tailscale_tailnet_key.homelab[k].key
      } : {}
    ) if try(local.homelab_fields[k].input, null) != null
  }

  # Extract parent router references for network inheritance
  homelab_parent = {
    for k, v in local.homelab_discovered : k => "router-${local.homelab_fields[k].input.parent}"
    if try(local.homelab_fields[k].input.parent, null) != null
  }

  # Determine which resources to create for each homelab item
  homelab_resources = {
    for k, v in local.homelab_discovered : k => {
      for resource in var.resources_homelab : resource =>
      contains(try(var.default_homelab_resources[v.platform], []), resource)
    }
  }
}
