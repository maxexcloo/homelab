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
        b2_application_key       = contains(local.homelab_flags[k].resources, "b2") ? b2_application_key.homelab[k].application_key : null
        b2_application_key_id    = contains(local.homelab_flags[k].resources, "b2") ? b2_application_key.homelab[k].application_key_id : null
        b2_bucket_name           = contains(local.homelab_flags[k].resources, "b2") ? b2_bucket.homelab[k].bucket_name : null
        b2_endpoint              = contains(local.homelab_flags[k].resources, "b2") ? replace(data.b2_account_info.default.s3_api_url, "https://", "") : null
        cloudflare_account_token = contains(local.homelab_flags[k].resources, "cloudflare") ? cloudflare_account_token.homelab[k].value : null
        cloudflare_tunnel_token  = contains(local.homelab_flags[k].resources, "cloudflare") ? data.cloudflare_zero_trust_tunnel_cloudflared_token.homelab[k].token : null
        desec_token              = contains(local.homelab_flags[k].resources, "desec") ? desec_token.homelab[k].token : null
        fqdn_external            = "${v.fqdn}.${var.domain_external}"
        fqdn_internal            = "${v.fqdn}.${var.domain_internal}"
        resend_api_key           = contains(local.homelab_flags[k].resources, "resend") ? jsondecode(restapi_object.resend_api_key_homelab[k].create_response).token : null
        tailscale_auth_key       = contains(local.homelab_flags[k].resources, "tailscale") ? tailscale_tailnet_key.homelab[k].key : null
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

  # Parse flags for each homelab item to determine resources and tags
  homelab_flags = {
    for k, v in local.homelab_discovered : k => {
      # Use explicit resource flags if present, otherwise use platform defaults
      resources = length([
        for flag in compact(split(",", replace(nonsensitive(try(local.homelab_onepassword_fields_input_raw[k].flags, "")), " ", ""))) :
        flag if contains(var.resources_homelab, flag)
        ]) > 0 ? [
        for flag in compact(split(",", replace(nonsensitive(try(local.homelab_onepassword_fields_input_raw[k].flags, "")), " ", ""))) :
        flag if contains(var.resources_homelab, flag)
      ] : try(var.default_homelab_resources[v.platform], [])

      # Tags are flags that aren't resources
      tags = [
        for flag in compact(split(",", replace(nonsensitive(try(local.homelab_onepassword_fields_input_raw[k].flags, "")), " ", ""))) : flag
        if !contains(var.resources_homelab, flag)
      ]
    }
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
