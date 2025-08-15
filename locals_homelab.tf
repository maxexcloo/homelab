locals {
  # Extract and normalize 1Password fields for each homelab item
  homelab_onepassword = {
    for k, v in local.homelab_discovered : k => {
      # Merged fields with schema defaults (all fields guaranteed to exist)
      fields = merge(
        # Start with all schema fields set to null
        {
          for field_name, field_type in merge(
            var.onepassword_homelab_field_schema.input,
            var.onepassword_homelab_field_schema.output
          ) : field_name => null
        },
        # Override with actual input values (convert "-" to null)
        {
          for field in try(data.onepassword_item.homelab_details[k].section[
            index(try(data.onepassword_item.homelab_details[k].section[*].label, []), "input")
          ].field, []) : field.label => field.value == "-" ? null : field.value
        },
        # Override with actual output values (convert "-" to null)
        {
          for field in try(data.onepassword_item.homelab_details[k].section[
            index(try(data.onepassword_item.homelab_details[k].section[*].label, []), "output")
          ].field, []) : field.label => field.value == "-" ? null : field.value
        }
      )

      # Raw input fields for sync back to 1Password (preserves "-" values)
      input_raw = {
        for field in try(data.onepassword_item.homelab_details[k].section[
          index(try(data.onepassword_item.homelab_details[k].section[*].label, []), "input")
        ].field, []) : field.label => field.value
      }
    } if try(data.onepassword_item.homelab_details[k], null) != null
  }

  # Determine which resources to create for each homelab item
  # TODO: Parse from 1Password resources field once sensitive value limitation is resolved
  homelab_resources = {
    for k, v in local.homelab_discovered : k => {
      for resource in var.resources_homelab : resource => contains(
        try(var.default_homelab_resources[v.platform], []),
        resource
      )
    }
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
        public_address = (
          local.homelab_onepassword[k].fields.public_address != null ?
          local.homelab_onepassword[k].fields.public_address :
          local.homelab_onepassword[k].fields.parent != null ?
          try(local.homelab_onepassword["router-${local.homelab_onepassword[k].fields.parent}"].fields.public_address, null) :
          null
        )

        public_ipv4 = (
          local.homelab_onepassword[k].fields.public_ipv4 != null ?
          local.homelab_onepassword[k].fields.public_ipv4 :
          local.homelab_onepassword[k].fields.parent != null ?
          try(local.homelab_onepassword["router-${local.homelab_onepassword[k].fields.parent}"].fields.public_ipv4, null) :
          null
        )

        public_ipv6 = (
          local.homelab_onepassword[k].fields.public_ipv6 != null ?
          local.homelab_onepassword[k].fields.public_ipv6 :
          local.homelab_onepassword[k].fields.parent != null ?
          try(local.homelab_onepassword["router-${local.homelab_onepassword[k].fields.parent}"].fields.public_ipv6, null) :
          null
        )

        # Path defaults based on username
        paths = (
          local.homelab_onepassword[k].fields.paths != null ?
          local.homelab_onepassword[k].fields.paths :
          data.onepassword_item.homelab_details[k].username == "root" ?
          "/root" :
          "/home/${data.onepassword_item.homelab_details[k].username}"
        )

        # Computed URLs and domains
        fqdn_external = "${v.fqdn}.${var.domain_external}"
        fqdn_internal = "${v.fqdn}.${var.domain_internal}"
        url = "${v.fqdn}.${var.domain_internal}${
          local.homelab_onepassword[k].fields.management_port != null ?
          ":${local.homelab_onepassword[k].fields.management_port}" : ""
        }"

        # Parse tags from comma-separated string
        tags = (
          local.homelab_onepassword[k].fields.tags != null ?
          split(",", replace(nonsensitive(local.homelab_onepassword[k].fields.tags), " ", "")) :
          []
        )

        # Tailscale device IPs (from device lookup)
        tailscale_ipv4 = try(local.tailscale_devices[k].tailscale_ipv4, null)
        tailscale_ipv6 = try(local.tailscale_devices[k].tailscale_ipv6, null)
      },

      # Layer 3: Resource-generated credentials (only if resource is enabled)
      {
        # Backblaze B2
        b2_application_key    = local.homelab_resources[k].b2 ? b2_application_key.homelab[k].application_key : null
        b2_application_key_id = local.homelab_resources[k].b2 ? b2_application_key.homelab[k].application_key_id : null
        b2_bucket_name        = local.homelab_resources[k].b2 ? b2_bucket.homelab[k].bucket_name : null
        b2_endpoint           = local.homelab_resources[k].b2 ? replace(data.b2_account_info.default.s3_api_url, "https://", "") : null

        # Cloudflare
        cloudflare_account_token = local.homelab_resources[k].cloudflare ? cloudflare_account_token.homelab[k].value : null
        cloudflare_tunnel_token  = local.homelab_resources[k].cloudflare ? data.cloudflare_zero_trust_tunnel_cloudflared_token.homelab[k].token : null

        # Resend
        resend_api_key = local.homelab_resources[k].resend ? jsondecode(restapi_object.resend_api_key_homelab[k].create_response).token : null

        # Tailscale
        tailscale_auth_key = local.homelab_resources[k].tailscale ? tailscale_tailnet_key.homelab[k].key : null
      }
    ) if contains(keys(local.homelab_onepassword), k)
  }
}