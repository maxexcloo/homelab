# Sync phase - Write service values back to 1Password

locals {
  services_field_schema = {
    input = {
      api_key           = "CONCEALED"
      database_password = "CONCEALED"
      description       = "STRING"
      dns               = "STRING"
      enable_b2         = "STRING"
      enable_monitoring = "STRING"
      enable_resend     = "STRING"
      flags             = "STRING"
      icon              = "STRING"
      secret_hash       = "CONCEALED"
      server            = "STRING"
      service           = "STRING"
    }
    output = {
      b2_application_key    = "CONCEALED"
      b2_application_key_id = "STRING"
      b2_bucket_name        = "STRING"
      b2_endpoint           = "URL"
      fqdn_external         = "URL"
      fqdn_internal         = "URL"
      platform        = "STRING"
      resend_api_key        = "CONCEALED"
    }
  }
}

resource "onepassword_item" "services_sync" {
  for_each = local.services_discovered

  title    = data.onepassword_item.services_details[each.key].title
  url      = try(local.services[each.key].url, null)
  username = data.onepassword_item.services_details[each.key].username
  vault    = data.onepassword_vault.services.uuid

  dynamic "section" {
    for_each = local.services_field_schema

    content {
      label = section.key

      dynamic "field" {
        for_each = section.value

        content {
          id    = "${section.key}.${field.key}"
          label = field.key
          type  = field.value

          # Logic: 
          # - Input fields: preserve existing raw values from 1Password (including "-")
          # - Output fields: always update with computed values (null becomes "-")
          value = section.key == "input" ? try(local.services_onepassword_fields_input_raw[each.key][field.key], "-") : coalesce(try(local.services[each.key][field.key], null), "-")
        }
      }
    }
  }
}
