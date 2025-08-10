# Discovery phase - List and fetch homelab items from 1Password

data "external" "homelab_item_list" {
  program = ["sh", "-c", "op item list --format=json --vault='${var.onepassword_vault_homelab}' | jq -c '{stdout: (. | tostring)}'"]

  depends_on = [random_id.homelab_refresh_trigger]
}

data "onepassword_item" "homelab_details" {
  for_each = local.homelab_discovered

  title = each.key
  vault = data.onepassword_vault.homelab.uuid

  depends_on = [random_id.homelab_refresh_trigger]
}

data "onepassword_vault" "homelab" {
  name = var.onepassword_vault_homelab
}

import {
  for_each = local.homelab_discovered

  id = "vaults/${data.onepassword_vault.homelab.uuid}/items/${each.value.id}"
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
}

output "homelab_discovered" {
  value     = keys(local.homelab_discovered)
  sensitive = false
}

# Force refresh of data sources on every run
resource "random_id" "homelab_refresh_trigger" {
  byte_length = 8

  keepers = {
    timestamp = timestamp()
  }
}
