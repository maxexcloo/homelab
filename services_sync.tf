# Sync phase - Write service values back to 1Password

locals {
  services_field_schema = {
    input = {
      description = "STRING"
      flags       = "STRING"
    }
    output = {
      # Output fields will be populated as services are implemented
      # Examples:
      # api_key     = "CONCEALED"
      # endpoint    = "URL"
      # status      = "STRING"
    }
  }
}

resource "onepassword_item" "services_sync" {
  for_each = local.services_discovered

  title    = data.onepassword_item.services_details[each.key].title
  username = data.onepassword_item.services_details[each.key].username
  vault    = data.onepassword_vault.services.uuid

  # URL field if available in computed services
  url = try(local.services[each.key].url, null)

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

          # Logic: preserve input fields from 1Password, update output fields with computed values
          value = section.key == "input" ? try(
            local.services_onepassword_fields[each.key][field.key],
            "-"
            ) : try(
            local.services[each.key][field.key],
            "-"
          )
        }
      }
    }
  }
}