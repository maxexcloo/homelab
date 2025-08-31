locals {
  # Extract fields from 1Password sections
  _extract_onepassword_fields = {
    for k, v in local.homelab_discovered : k => {
      input_section  = try([for s in data.onepassword_item.homelab_details[k].section : s if s.label == "input"][0], null)
      output_section = try([for s in data.onepassword_item.homelab_details[k].section : s if s.label == "output"][0], null)
    } if try(data.onepassword_item.homelab_details[k], null) != null
  }

  # Complete homelab data with all fields merged and computed
  homelab = {
    for k, v in local.homelab_discovered : k => merge(
      # Base: Discovery metadata
      v,

      # Layer 1: All 1Password fields (guaranteed to exist with nulls)
      try(local.homelab_onepassword[k].fields, {}),

      # Layer 2: Computed and inherited fields
      {
        # Network inheritance (child inherits from parent router if not set)
        public_address = try(
          coalesce(
            local.homelab_onepassword[k].fields.public_address,
            local.homelab_onepassword[local.homelab_parent_routers[k]].fields.public_address
          ),
          null
        )

        public_ipv4 = try(
          coalesce(
            local.homelab_onepassword[k].fields.public_ipv4,
            local.homelab_onepassword[local.homelab_parent_routers[k]].fields.public_ipv4
          ),
          null
        )

        public_ipv6 = try(
          coalesce(
            local.homelab_onepassword[k].fields.public_ipv6,
            local.homelab_onepassword[local.homelab_parent_routers[k]].fields.public_ipv6
          ),
          null
        )

        # Path defaults based on username
        paths = try(
          coalesce(local.homelab_onepassword[k].fields.paths),
          data.onepassword_item.homelab_details[k].username == "root" ? "/root" : "/home/${data.onepassword_item.homelab_details[k].username}"
        )

        # Computed URLs and domains
        fqdn_external = "${v.fqdn}.${var.domain_external}"
        fqdn_internal = "${v.fqdn}.${var.domain_internal}"
        url           = "${v.fqdn}.${var.domain_internal}${try(":${local.homelab_onepassword[k].fields.management_port}", "")}"

        # Parse tags from comma-separated string
        tags = try(split(",", replace(local.homelab_onepassword[k].fields.tags, " ", "")), [])

        # Tailscale device IPs (from device lookup)
        tailscale_ipv4 = try(local.tailscale_device_addresses[v.title].ipv4, null)
        tailscale_ipv6 = try(local.tailscale_device_addresses[v.title].ipv6, null)
      },

      # Layer 3: Resource-generated credentials
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
    ) if try(local.homelab_onepassword[k], null) != null
  }

  # Extract and normalize 1Password fields for each homelab item
  homelab_onepassword = {
    for k, v in local._extract_onepassword_fields : k => {
      # Merged fields with schema defaults (all fields guaranteed to exist)
      fields = merge(
        # Start with all schema fields set to null
        {
          for field_name, field_type in merge(
            var.onepassword_homelab_field_schema.input,
            var.onepassword_homelab_field_schema.output
          ) : field_name => null
        },
        # Override with actual values (convert "-" to null)
        {
          for field in try(v.input_section.field, []) : field.label => field.value == "-" ? null : field.value
        },
        {
          for field in try(v.output_section.field, []) : field.label => field.value == "-" ? null : field.value
        }
      )

      # Raw input fields for sync back to 1Password (preserves "-" values)
      input_raw = {
        for field in try(v.input_section.field, []) : field.label => field.value
      }
    }
  }

  # Extract parent router references for network inheritance
  homelab_parent_routers = {
    for k, v in local.homelab_discovered : k =>
    "router-${local.homelab_onepassword[k].fields.parent}"
    if try(local.homelab_onepassword[k].fields.parent, null) != null
  }

  # Determine which resources to create for each homelab item
  homelab_resources = {
    for k, v in local.homelab_discovered : k => {
      for resource in var.resources_homelab : resource =>
      contains(try(var.default_homelab_resources[v.platform], []), resource)
    }
  }
}