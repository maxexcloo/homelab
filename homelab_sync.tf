resource "onepassword_item" "homelab_sync" {
  for_each = local.homelab_id_to_title

  title    = data.onepassword_item.homelab_details[each.value].title
  url      = local.homelab[each.value].url
  username = data.onepassword_item.homelab_details[each.value].username
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
          # - Input fields: preserve existing raw values from 1Password (including "-")
          # - Output fields: always update with computed values (null becomes "-")
          value = section.key == "input" ? try(local.homelab_onepassword[each.value].input_raw[field.key], "-") : coalesce(try(local.homelab[each.value][field.key], null), "-")
        }
      }
    }
  }

  lifecycle {
    # Validate parent exists if specified
    precondition {
      condition     = try(local.homelab_onepassword[each.value].fields.parent == null || contains(keys(local.homelab_discovered), "router-${local.homelab_onepassword[each.value].fields.parent}"), true)
      error_message = "Parent '${nonsensitive(try(coalesce(local.homelab_onepassword[each.value].fields.parent, "none"), "unknown"))}' does not exist for ${each.value}. Expected format: router-{region}"
    }

    # Validate title format
    precondition {
      condition     = can(regex("^[a-z]+-[a-z]+-[a-z0-9]+$", each.value)) || can(regex("^router-[a-z]+$", each.value))
      error_message = "Item ${each.value} must follow pattern: platform-region-name (e.g., vm-au-hsp) or router-region (e.g., router-au)"
    }
  }
}
