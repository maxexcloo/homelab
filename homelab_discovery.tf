data "external" "homelab_item_list" {
  program = ["sh", "-c", "op item list --format=json --vault='${var.onepassword_homelab_vault}' | jq -c '{stdout: (. | tostring)}'"]
}

data "onepassword_item" "homelab_details" {
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
  # Parse raw items from 1Password
  _homelab_raw = {
    for item in jsondecode(data.external.homelab_item_list.result.stdout) : item.title => {
      id        = item.id
      parts     = split("-", item.title)
      name_part = length(split("-", item.title)) > 2 ? join("-", slice(split("-", item.title), 2, length(split("-", item.title)))) : null
    } if can(regex("^[a-z]+-[a-z]+-[a-z]+$", item.title)) || can(regex("^router-[a-z]+$", item.title))
  }

  # Extract metadata from naming convention
  homelab_discovered = {
    for title, item in local._homelab_raw : title => {
      fqdn     = item.name_part != null ? "${item.name_part}.${item.parts[1]}" : item.parts[1]
      id       = item.id
      name     = item.name_part != null ? item.name_part : item.parts[1]
      platform = item.parts[0]
      region   = item.parts[1]
      title    = replace(title, "/^[a-z]+-/", "")
    }
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
