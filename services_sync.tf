resource "onepassword_item" "services_sync" {
  for_each = local.services_id_to_title

  title    = each.value
  url      = local.services[each.value].url
  username = local.services[each.value].username
  vault    = data.onepassword_vault.services.uuid

  # Input section (always present)
  dynamic "section" {
    for_each = { input = var.onepassword_services_field_schema.input }

    content {
      label = section.key

      dynamic "field" {
        for_each = section.value

        content {
          id    = "${section.key}.${field.key}"
          label = field.key
          type  = field.value
          value = coalesce(lookup(local.services[each.value].input, field.key, null), "-")
        }
      }
    }
  }

  # Output sections (per-target, always present)
  dynamic "section" {
    for_each = local.services[each.value].output

    content {
      label = section.key

      dynamic "field" {
        for_each = {
          for k, v in var.onepassword_services_field_schema.output : k => v
          if lookup(section.value, k, null) != null
        }

        content {
          id    = "${section.key}.${field.key}"
          label = field.key
          type  = field.value
          value = section.value[field.key]
        }
      }
    }
  }

  lifecycle {
    # Validate deploy_to references
    precondition {
      condition = (
        local.services[each.value].input.deploy_to == null ||
        # Deploy to all
        local.services[each.value].input.deploy_to == "all" ||
        # Direct server reference
        contains(keys(local.homelab_discovered), local.services[each.value].input.deploy_to) ||
        # Platform/region/tag reference
        can(regex("^(platform|region|tag):", local.services[each.value].input.deploy_to))
      )
      error_message = "Invalid deploy_to for service ${each.value}. Must be all, a server title, or platform:x, region:x, tag:x"
    }

    # Validate services with custom URLs deploy to exactly one server
    precondition {
      condition = (
        local.services[each.value].url == null ||
        length(local.services_deployments[each.value]) == 1
      )
      error_message = "Service ${each.value} has a custom URL but deploys to ${length(local.services_deployments[each.value])} servers. Services with custom URLs must deploy to exactly one server."
    }
  }
}
