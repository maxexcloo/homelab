resource "onepassword_item" "homelab_sync" {
  for_each = local.homelab_id_to_title

  title    = each.value
  url      = local.homelab[each.value].url
  username = local.homelab[each.value].username
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
          value = coalesce(lookup(lookup(local.homelab[each.value], section.key, {}), field.key, null), "-")
        }
      }
    }
  }

  lifecycle {
    # Validate parent exists if specified
    precondition {
      condition     = local.homelab_discovered[each.value].input.parent == null || contains(keys(local.homelab_discovered), local.homelab_discovered[each.value].input.parent)
      error_message = "Parent does not exist for ${each.value}."
    }
  }
}
