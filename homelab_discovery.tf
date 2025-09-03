# Get all items from vault using 1Password Connect API via mise
data "external" "homelab_items" {
  program = ["sh", "-c", "mise exec -- sh -c 'curl -s -H \"Authorization: Bearer $OP_CONNECT_TOKEN\" \"$OP_CONNECT_HOST/v1/vaults/${data.onepassword_vault.homelab.uuid}/items\" | jq -c \"[.[] | {id, title}] | {items: (. | tostring)}\" || echo \"{\\\"items\\\":\\\"[]\\\"}\"'"]
}

data "onepassword_item" "homelab" {
  for_each = local.homelab_discovered

  title = each.key
  vault = data.onepassword_vault.homelab.uuid
}

data "onepassword_vault" "homelab" {
  name = var.onepassword_homelab_vault
}

import {
  for_each = local.homelab_id_to_title

  id = "vaults/${data.onepassword_vault.homelab.uuid}/items/${each.key}"
  to = onepassword_item.homelab_sync[each.key]
}

locals {
  # Parse raw items from 1Password Connect API and extract metadata from naming convention
  homelab_discovered = {
    for item in jsondecode(data.external.homelab_items.result.items) : item.title => {
      fqdn     = length(split("-", item.title)) > 2 ? "${join("-", slice(split("-", item.title), 2, length(split("-", item.title))))}.${split("-", item.title)[1]}" : split("-", item.title)[1]
      id       = item.id
      name     = length(split("-", item.title)) > 2 ? join("-", slice(split("-", item.title), 2, length(split("-", item.title)))) : split("-", item.title)[1]
      platform = split("-", item.title)[0]
      region   = split("-", item.title)[1]
      title    = replace(item.title, "/^[a-z]+-/", "")
    } if can(regex("^[a-z]+-[a-z]+-[a-z]+$", item.title)) || can(regex("^router-[a-z]+$", item.title))
  }

  # Process 1Password fields separately to avoid circular dependency
  homelab_fields = {
    for k, v in local.homelab_discovered : k => merge(
      # Input fields with defaults from schema
      {
        input = merge(
          # Start with all schema input fields set to null
          {
            for field_name, field_type in var.onepassword_homelab_field_schema.input : field_name => null
          },
          # Override with actual values from 1Password (when item exists), converting "-" to null
          try(data.onepassword_item.homelab[k], null) != null ? {
            for field in try([for s in data.onepassword_item.homelab[k].section : s if s.label == "input"][0].field, []) : field.label => field.value == "-" ? null : field.value
          } : {}
        )

        # Output fields with defaults from schema
        output = merge(
          # Start with all schema output fields set to null
          {
            for field_name, field_type in var.onepassword_homelab_field_schema.output : field_name => null
          },
          # Override with actual values from 1Password (when item exists), converting "-" to null
          try(data.onepassword_item.homelab[k], null) != null ? {
            for field in try([for s in data.onepassword_item.homelab[k].section : s if s.label == "output"][0].field, []) : field.label => field.value == "-" ? null : field.value
          } : {}
        )
      }
    )
  }

  # Simple ID to title mapping for 1Password sync resources
  homelab_id_to_title = {
    for title, item in local.homelab_discovered : item.id => title
  }
}

output "homelab_discovered" {
  value     = keys(local.homelab_discovered)
  sensitive = false
}
