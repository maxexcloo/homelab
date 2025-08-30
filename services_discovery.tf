data "external" "services_item_list" {
  program = ["sh", "-c", "op item list --format=json --vault='${var.onepassword_services_vault}' | jq -c '{stdout: (. | tostring)}'"]
}

data "onepassword_item" "services_details" {
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

# Parse raw items from 1Password
locals {
  _services_raw = {
    for item in jsondecode(data.external.services_item_list.result.stdout) : item.title => {
      id    = item.id
      parts = split("-", item.title)
    } if can(regex("^[a-z]+-[a-z]+", item.title))
  }

  # Extract metadata from naming convention
  services_discovered = {
    for title, item in local._services_raw : title => {
      id       = item.id
      name     = join("-", slice(item.parts, 1, length(item.parts)))
      platform = item.parts[0]
    }
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