# Processing phase - Extract fields and compute final values

locals {
  # Complete homelab structure with inheritance and computed fields
  homelab = {
    for k, v in local.homelab_discovered : k => merge(
      v,                                   # Base metadata (fqdn, name, platform, region, title)
      local.homelab_onepassword_fields[k], # 1Password fields
      # Computed fields
      {
        # Resource-generated fields (conditional based on flags)
        b2_application_key       = local.homelab_resources[k].b2 ? b2_application_key.homelab[k].application_key : null
        b2_application_key_id    = local.homelab_resources[k].b2 ? b2_application_key.homelab[k].application_key_id : null
        b2_bucket_name           = local.homelab_resources[k].b2 ? b2_bucket.homelab[k].bucket_name : null
        b2_endpoint              = local.homelab_resources[k].b2 ? replace(data.b2_account_info.default.s3_api_url, "https://", "") : null
        cloudflare_account_token = local.homelab_resources[k].cloudflare ? cloudflare_account_token.homelab[k].value : null
        cloudflare_tunnel_token  = local.homelab_resources[k].cloudflare ? data.cloudflare_zero_trust_tunnel_cloudflared_token.homelab[k].token : null
        fqdn_external            = "${v.fqdn}.${var.domain_external}"
        fqdn_internal            = "${v.fqdn}.${var.domain_internal}"
        resend_api_key           = local.homelab_resources[k].resend ? jsondecode(restapi_object.resend_api_key_homelab[k].create_response).token : null
        tags                     = split(",", replace(nonsensitive(try(local.homelab_onepassword_fields_input_raw[k].tags, "")), " ", ""))
        tailscale_auth_key       = local.homelab_resources[k].tailscale ? tailscale_tailnet_key.homelab[k].key : null
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

  # Parse resources for each homelab item to determine which resources to create
  homelab_resources = {
    for k, v in local.homelab_discovered : k => merge(
      # Create a boolean flag for each possible resource type
      {
        for resource in var.resources_homelab : resource => contains(
          # Parse the resources field, validate against allowed resources, and use defaults if empty
          length([
            for r in split(",", replace(nonsensitive(try(local.homelab_onepassword_fields_input_raw[k].resources, "")), " ", "")) :
            r if contains(var.resources_homelab, r)
            ]) > 0 ? [
            for r in split(",", replace(nonsensitive(try(local.homelab_onepassword_fields_input_raw[k].resources, "")), " ", "")) :
            r if contains(var.resources_homelab, r)
          ] : try(var.default_homelab_resources[v.platform], []),
          resource
        )
      }
    )
  }
}
