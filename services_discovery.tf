data "http" "service_item" {
  for_each = {
    for item in jsondecode(data.http.services_vault.response_body) : item.title => item.id
    if can(regex("^[a-z0-9]+-[a-z0-9]+(?:-[a-z0-9-]+)?$", item.title))
  }

  url = "${var.onepassword_connect_host}/v1/vaults/${data.onepassword_vault.services.uuid}/items/${each.value}"

  request_headers = {
    Authorization = "Bearer ${var.onepassword_connect_token}"
  }
}

data "http" "services_vault" {
  url = "${var.onepassword_connect_host}/v1/vaults/${data.onepassword_vault.services.uuid}/items"

  request_headers = {
    Authorization = "Bearer ${var.onepassword_connect_token}"
  }
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
  # Helper to parse JSON data once per item
  _services_item_data = {
    for title, item in data.http.service_item : title => jsondecode(item.response_body)
  }

  # Build complete discovered items directly from individual item data sources
  services_discovered = {
    for title, item in local._services_item_data : title => merge(
      # Standardized naming conventions
      {
        id       = item.id
        name     = join("-", slice(split("-", title), 1, length(split("-", title))))
        platform = split("-", title)[0]
        username = try([for field in item.fields : field.value if try(field.purpose, null) == "USERNAME"][0], null)
        url      = try(item.urls[0].href, null)
      },
      # Input fields nested under 'input' key
      {
        input = merge(
          # Start with schema defaults
          {
            for field_name, field_type in var.onepassword_services_field_schema.input : field_name => null
          },
          # Add platform-specific resource defaults
          {
            resources = length(lookup(var.resources_services_defaults, split("-", title)[0], [])) > 0 ? join(",", lookup(var.resources_services_defaults, split("-", title)[0], [])) : ""
          },
          # Override with actual values from 1Password
          {
            for field in item.fields : field.label => field.value == "-" || field.value == "" ? null : field.value
            if try(field.section.label, "") == "input"
          }
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
