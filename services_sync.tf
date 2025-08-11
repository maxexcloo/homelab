# Sync phase - Write service values back to 1Password

resource "onepassword_item" "services_sync" {
  for_each = local.services_id_to_title

  title    = data.onepassword_item.services_details[each.value].title
  url      = try(local.services[each.value].url, null)
  username = data.onepassword_item.services_details[each.value].username
  vault    = data.onepassword_vault.services.uuid

  dynamic "section" {
    for_each = var.onepassword_item_services_field_schema

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
          value = section.key == "input" ? try(local.services_onepassword_fields_input_raw[each.value][field.key], "-") : coalesce(try(local.services[each.value][field.key], null), "-")
        }
      }
    }
  }
}
