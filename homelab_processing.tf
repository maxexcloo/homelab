# Processing phase - Extract fields and compute final values

locals {
  # Complete homelab structure with inheritance and computed fields
  homelab = {
    for k, v in local.homelab_discovered : k => merge(
      v,                                   # Base metadata (fqdn, name, platform, region, title)
      local.homelab_onepassword_fields[k], # 1Password fields
      # Computed fields
      {
        # Resource-generated fields
        b2_application_key       = b2_application_key.homelab[k].application_key
        b2_application_key_id    = b2_application_key.homelab[k].application_key_id
        b2_bucket_name           = b2_bucket.homelab[k].bucket_name
        b2_endpoint              = replace(data.b2_account_info.default.s3_api_url, "https://", "")
        cloudflare_account_token = cloudflare_account_token.homelab[k].value
        cloudflare_tunnel_token  = data.cloudflare_zero_trust_tunnel_cloudflared_token.homelab[k].token
        fqdn_external            = "${v.fqdn}.${var.domain_external}"
        fqdn_internal            = "${v.fqdn}.${var.domain_internal}"
        resend_api_key           = jsondecode(restapi_object.resend_api_key_homelab[k].create_response).token
        tailscale_auth_key       = tailscale_tailnet_key.homelab[k].key
        tailscale_ipv4           = try(local.tailscale_devices[k].tailscale_ipv4, null)
        tailscale_ipv6           = try(local.tailscale_devices[k].tailscale_ipv6, null)
        url                      = "${v.fqdn}.${var.domain_internal}${local.homelab_onepassword_fields[k].management_port != null ? ":${local.homelab_onepassword_fields[k].management_port}" : ""}"

        # Paths with default
        paths = try(
          local.homelab_onepassword_fields[k].paths,
          data.onepassword_item.homelab_details[k].username == "root" ? "/root" : "/home/${data.onepassword_item.homelab_details[k].username}"
        )

        # Network fields with inheritance
        # If field has a value (not null), use it; otherwise try to inherit from parent
        public_address = try(
          local.homelab_onepassword_fields[k].public_address,
          local.homelab_onepassword_fields["router-${local.homelab_onepassword_fields[k].parent}"].public_address,
          null
        )
        public_ipv4 = try(
          local.homelab_onepassword_fields[k].public_ipv4,
          local.homelab_onepassword_fields["router-${local.homelab_onepassword_fields[k].parent}"].public_ipv4,
          null
        )
        public_ipv6 = try(
          local.homelab_onepassword_fields[k].public_ipv6,
          local.homelab_onepassword_fields["router-${local.homelab_onepassword_fields[k].parent}"].public_ipv6,
          null
        )
      }
    ) if contains(keys(local.homelab_onepassword_fields), k)
  }

  # Extract 1Password fields for each homelab item
  homelab_onepassword_fields = {
    for k, v in local.homelab_discovered : k => merge(
      # Extract input section fields (convert "-" to null for consistent processing)
      {
        for field in try(data.onepassword_item.homelab_details[k].section[index(try(data.onepassword_item.homelab_details[k].section[*].label, []), "input")].field, []) :
        field.label => field.value == "-" ? null : field.value
      },
      # Extract output section fields (convert "-" to null for consistent processing)
      {
        for field in try(data.onepassword_item.homelab_details[k].section[index(try(data.onepassword_item.homelab_details[k].section[*].label, []), "output")].field, []) :
        field.label => field.value == "-" ? null : field.value
      }
    ) if try(data.onepassword_item.homelab_details[k], null) != null
  }

  # Keep track of original input field values for sync
  homelab_onepassword_fields_input_raw = {
    for k, v in local.homelab_discovered : k => {
      for field in try(data.onepassword_item.homelab_details[k].section[index(try(data.onepassword_item.homelab_details[k].section[*].label, []), "input")].field, []) : field.label => field.value
    } if try(data.onepassword_item.homelab_details[k], null) != null
  }
}
