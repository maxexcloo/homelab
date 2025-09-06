data "http" "service_item" {
  for_each = {
    for item in jsondecode(data.http.services_vault.response_body) : item.title => item.id
    if can(regex("^[a-z]+-[a-z]+", item.title))
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
  # Build complete discovered items directly from individual item data sources
  services_discovered = {
    for title, item_data in data.http.service_item : title => merge(
      # Base metadata from title parsing
      {
        id       = jsondecode(item_data.response_body).id
        name     = join("-", slice(split("-", title), 1, length(split("-", title))))
        platform = split("-", title)[0]
        username = try([for field in jsondecode(item_data.response_body).fields : field.value if field.purpose == "USERNAME"][0], null)
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
            resources = join(",", lookup(var.resources_services_defaults, split("-", title)[0], []))
          },
          # Override with actual values from 1Password
          {
            for field in try([for s in jsondecode(item_data.response_body).sections : s if s.label == "input"][0].fields, []) : field.label => field.value == "-" ? null : field.value
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
