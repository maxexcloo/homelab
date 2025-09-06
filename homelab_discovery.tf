data "http" "homelab_item" {
  for_each = {
    for item in jsondecode(data.http.homelab_vault.response_body) : item.title => item.id
    if can(regex("^[a-z]+-[a-z]+-[a-z]+$", item.title)) || can(regex("^router-[a-z]+$", item.title))
  }

  url = "${var.onepassword_connect_host}/v1/vaults/${data.onepassword_vault.homelab.uuid}/items/${each.value}"

  request_headers = {
    Authorization = "Bearer ${var.onepassword_connect_token}"
  }
}

data "http" "homelab_vault" {
  url = "${var.onepassword_connect_host}/v1/vaults/${data.onepassword_vault.homelab.uuid}/items"

  request_headers = {
    Authorization = "Bearer ${var.onepassword_connect_token}"
  }
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
  # Build complete discovered items directly from individual item data sources
  homelab_discovered = {
    for title, item_data in data.http.homelab_item : title => merge(
      # Base metadata from title parsing
      {
        fqdn     = length(split("-", title)) > 2 ? "${join("-", slice(split("-", title), 2, length(split("-", title))))}.${split("-", title)[1]}" : split("-", title)[1]
        id       = jsondecode(item_data.response_body).id
        name     = length(split("-", title)) > 2 ? join("-", slice(split("-", title), 2, length(split("-", title)))) : split("-", title)[1]
        platform = split("-", title)[0]
        region   = split("-", title)[1]
        title    = replace(title, "/^[a-z]+-/", "")
        username = try([for field in jsondecode(item_data.response_body).fields : field.value if field.purpose == "USERNAME"][0], null)
      },
      # Input fields nested under 'input' key
      {
        input = merge(
          # Start with schema defaults
          {
            for field_name, field_type in var.onepassword_homelab_field_schema.input : field_name => null
          },
          # Add platform-specific resource defaults
          {
            resources = join(",", lookup(var.resources_homelab_defaults, split("-", title)[0], []))
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
  homelab_id_to_title = {
    for title, item in local.homelab_discovered : item.id => title
  }
}

output "homelab_discovered" {
  value     = keys(local.homelab_discovered)
  sensitive = false
}
