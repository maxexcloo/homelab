# Get all items from vault using 1Password Connect API via mise
data "external" "services_items" {
  program = ["sh", "-c", "mise exec -- sh -c 'curl -s -H \"Authorization: Bearer $OP_CONNECT_TOKEN\" \"$OP_CONNECT_HOST/v1/vaults/${data.onepassword_vault.services.uuid}/items\" | jq -c \"[.[] | {id, title}] | {items: (. | tostring)}\" || echo \"{\\\"items\\\":\\\"[]\\\"}\"'"]
}

data "onepassword_item" "service" {
  for_each = local.services_discovered

  title = each.key
  vault = data.onepassword_vault.services.uuid
}

data "onepassword_vault" "services" {
  name = var.onepassword_services_vault
}

import {
  for_each = local.services_id_to_title

  id = "vaults/${data.onepassword_vault.services.uuid}/items/${each.key}"
  to = onepassword_item.services_sync[each.key]
}

locals {
  # Parse raw items from 1Password Connect API and extract metadata from naming convention
  services_discovered = {
    for item in jsondecode(data.external.services_items.result.items) : item.title => {
      id       = item.id
      name     = join("-", slice(split("-", item.title), 1, length(split("-", item.title))))
      platform = split("-", item.title)[0]
    } if can(regex("^[a-z]+-[a-z]+", item.title))
  }

  # Process 1Password fields separately to avoid circular dependency
  services_fields = {
    for k, v in local.services_discovered : k => merge(
      # Input fields with defaults from schema
      {
        input = merge(
          # Start with all schema input fields set to null
          {
            for field_name, field_type in var.onepassword_services_field_schema.input : field_name => null
          },
          # Override with actual values from 1Password (when item exists), converting "-" to null
          try(data.onepassword_item.service[k], null) != null ? {
            for field in try([for s in data.onepassword_item.service[k].section : s if s.label == "input"][0].field, []) : field.label => field.value == "-" ? null : field.value
          } : {}
        )

        # Output fields with defaults from schema
        output = merge(
          # Start with all schema output fields set to null
          {
            for field_name, field_type in var.onepassword_services_field_schema.output : field_name => null
          },
          # Override with actual values from 1Password (when item exists), converting "-" to null
          try(data.onepassword_item.service[k], null) != null ? {
            for field in try([for s in data.onepassword_item.service[k].section : s if s.label == "output"][0].field, []) : field.label => field.value == "-" ? null : field.value
          } : {}
        )
      }
    )
  }

  # Simple ID to title mapping for 1Password sync resources
  services_id_to_title = {
    for title, item in local.services_discovered : item.id => title
  }
}

output "services_discovered" {
  value     = keys(local.services_discovered)
  sensitive = false
}
