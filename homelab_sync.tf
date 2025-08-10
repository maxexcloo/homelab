# Sync phase - Write homelab values back to 1Password

locals {
  homelab_field_schema = {
    input = {
      description     = "STRING"
      flags           = "STRING"
      management_port = "STRING"
      parent          = "STRING"
      paths           = "STRING"
      private_ipv4    = "URL"
      public_address  = "URL"
      public_ipv4     = "URL"
      public_ipv6     = "URL"
    }
    output = {
      b2_application_key       = "CONCEALED"
      b2_application_key_id    = "STRING"
      b2_bucket_name           = "STRING"
      b2_endpoint              = "URL"
      cloudflare_account_token = "CONCEALED"
      cloudflare_tunnel_token  = "CONCEALED"
      fqdn_external            = "URL"
      fqdn_internal            = "URL"
      public_address           = "URL"
      region                   = "STRING"
      resend_api_key           = "CONCEALED"
      tailscale_auth_key       = "CONCEALED"
      tailscale_ipv4           = "URL"
      tailscale_ipv6           = "URL"
    }
  }
}

resource "onepassword_item" "homelab_sync" {
  for_each = local.homelab_discovered

  title    = data.onepassword_item.homelab_details[each.key].title
  url      = local.homelab[each.key].url
  username = data.onepassword_item.homelab_details[each.key].username
  vault    = data.onepassword_vault.homelab.uuid

  dynamic "section" {
    for_each = local.homelab_field_schema

    content {
      label = section.key

      dynamic "field" {
        for_each = section.value

        content {
          id    = "${section.key}.${field.key}"
          label = field.key
          type  = field.value

          # Logic: preserve input fields from 1Password, update output fields with computed values
          value = section.key == "input" ? try(
            local.homelab_onepassword_fields[each.key][field.key],
            "-"
            ) : try(
            local.homelab[each.key][field.key],
            "-"
          )
        }
      }
    }
  }
}
