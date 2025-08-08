locals {
  homelab_field_types = {
    input = {
      description    = "STRING"
      flags          = "STRING"
      parent         = "STRING"
      paths          = "STRING"
      private_ipv4   = "URL"
      public_address = "URL"
      public_ipv4    = "URL"
      public_ipv6    = "URL"
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

resource "onepassword_item" "homelab" {
  for_each = local.onepassword_vault_homelab

  title    = data.onepassword_item.homelab[each.key].title
  url      = try(local.homelab[each.key].fqdn_internal, "https://${each.value.fqdn}.${var.domain_internal}")
  username = data.onepassword_item.homelab[each.key].username
  vault    = data.onepassword_vault.homelab.uuid

  dynamic "section" {
    for_each = local.homelab_field_types

    content {
      label = section.key

      dynamic "field" {
        for_each = section.value

        content {
          id    = "${section.key}.${field.key}"
          label = field.key
          type  = field.value
          value = coalesce(try(local.homelab[each.key][field.key], null), "-")
        }
      }
    }
  }
}

resource "onepassword_item" "services" {
  for_each = local.onepassword_vault_services

  title    = data.onepassword_item.services[each.key].title
  username = data.onepassword_item.services[each.key].username
  vault    = data.onepassword_vault.services.uuid
}
