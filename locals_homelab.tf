locals {
  # Complete homelab structure with inheritance and computed fields
  homelab = {
    for k, v in local.onepassword_vault_homelab : k => merge(
      local.homelab_fields[k], # 1Password fields
      v,                       # Base metadata (fqdn, name, platform, region, title)
      # Computed fields
      {
        # Resource-generated fields
        b2_application_key       = b2_application_key.homelab[k].application_key
        b2_application_key_id    = b2_application_key.homelab[k].application_key_id
        b2_bucket_name           = b2_bucket.homelab[k].bucket_name
        b2_endpoint              = replace(data.b2_account_info.default.s3_api_url, "https://", "")
        cloudflare_account_token = cloudflare_account_token.homelab[k].value
        cloudflare_tunnel_token  = null # Placeholder
        fqdn_external            = "${v.fqdn}.${var.domain_external}"
        fqdn_internal            = "${v.fqdn}.${var.domain_internal}"
        resend_api_key           = jsondecode(restapi_object.resend_api_key_homelab[k].create_response).token
        tailscale_auth_key       = tailscale_tailnet_key.homelab[k].key
        tailscale_ipv4           = try(local.tailscale_devices[k].tailscale_ipv4, null)
        tailscale_ipv6           = try(local.tailscale_devices[k].tailscale_ipv6, null)

        # Paths with default
        paths = try(
          local.homelab_fields[k].paths,
          data.onepassword_item.homelab[k].username == "root" ? "/root" : "/home/${data.onepassword_item.homelab[k].username}"
        )

        # Network fields with inheritance
        public_address = try(
          local.homelab_fields[k].public_address,
          local.homelab_fields["router-${local.homelab_fields[k].parent}"].public_address,
          null
        )
        public_ipv4 = try(
          local.homelab_fields[k].public_ipv4,
          local.homelab_fields["router-${local.homelab_fields[k].parent}"].public_ipv4,
          null
        )
        public_ipv6 = try(
          local.homelab_fields[k].public_ipv6,
          local.homelab_fields["router-${local.homelab_fields[k].parent}"].public_ipv6,
          null
        )
      }
    ) if contains(keys(local.homelab_fields), k)
  }

  # Extract 1Password fields for each homelab item
  homelab_fields = {
    for k, v in local.onepassword_vault_homelab : k => merge(
      # Extract input section fields
      {
        for field in try(data.onepassword_item.homelab[k].section[index(try(data.onepassword_item.homelab[k].section[*].label, []), "input")].field, []) :
        field.label => field.value == "-" ? null : field.value
      },
      # Extract output section fields  
      {
        for field in try(data.onepassword_item.homelab[k].section[index(try(data.onepassword_item.homelab[k].section[*].label, []), "output")].field, []) :
        field.label => field.value == "-" ? null : field.value
      }
    ) if try(data.onepassword_item.homelab[k], null) != null
  }
}
