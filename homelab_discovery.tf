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
  # Parse homelab vault items - extract metadata from naming convention
  homelab_discovered = {
    for item in jsondecode(data.external.homelab_item_list.result.stdout) : item.title => {
      id       = item.id
      platform = split("-", item.title)[0]
      region   = split("-", item.title)[1]
      title    = replace(item.title, "/^[a-z]+-/", "")
      fqdn = (
        can(regex("^[a-z]+-[a-z]+-", item.title)) ?
        "${replace(item.title, "/^[a-z]+-[a-z]+-/", "")}.${split("-", item.title)[1]}" :
        split("-", item.title)[1]
      )
      name = (
        can(regex("^[a-z]+-[a-z]+-", item.title)) ?
        replace(item.title, "/^[a-z]+-[a-z]+-/", "") :
        replace(item.title, "/^[a-z]+-/", "")
      )
    } if can(regex("^[a-z]+-[a-z]+", item.title))
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
