resource "onepassword_item" "homelab_sync" {
  for_each = local.homelab_id_to_title

  title    = data.onepassword_item.homelab[each.value].title
  url      = local.homelab[each.value].url
  username = data.onepassword_item.homelab[each.value].username
  vault    = data.onepassword_vault.homelab.uuid

  dynamic "section" {
    for_each = var.onepassword_homelab_field_schema

    content {
      label = section.key

      dynamic "field" {
        for_each = section.value

        content {
          id    = "${section.key}.${field.key}"
          label = field.key
          type  = field.value

          # Logic:
          # - Input fields: preserve existing values from 1Password (including "-")
          # - Output fields: always update with computed values (null becomes "-")
          value = section.key == "input" ? coalesce(local.homelab_fields[each.value].input[field.key], "-") : coalesce(try(local.homelab[each.value][field.key], null), "-")
        }
      }
    }
  }

  lifecycle {
    # Validate parent exists if specified
    precondition {
      condition     = try(local.homelab_fields[each.value].input.parent == null || contains(keys(local.homelab_discovered), "router-${local.homelab_fields[each.value].input.parent}"), true)
      error_message = "Parent router does not exist for ${each.value}. Expected format: router-{region}"
    }
  }
}
