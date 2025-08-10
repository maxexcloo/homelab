# Discovery phase - List and fetch service items from 1Password

data "external" "services_item_list" {
  program = ["sh", "-c", "op item list --format=json --vault='${var.onepassword_vault_services}' | jq -c '{stdout: (. | tostring)}'"]

  depends_on = [random_id.services_refresh_trigger]
}

data "onepassword_item" "services_details" {
  for_each = local.services_discovered

  title = each.key
  vault = data.onepassword_vault.services.uuid

  depends_on = [random_id.services_refresh_trigger]
}

data "onepassword_vault" "services" {
  name = var.onepassword_vault_services
}

import {
  for_each = local.services_discovered

  id = "vaults/${data.onepassword_vault.services.uuid}/items/${each.value.id}"
  to = onepassword_item.services_sync[each.key]
}

locals {
  # Parse services vault items - extract metadata from naming convention
  services_discovered = {
    for item in jsondecode(data.external.services_item_list.result.stdout) : item.title => {
      id       = item.id
      name     = replace(item.title, "/^[^-]*-/", "")
      platform = split("-", item.title)[0]
    } if can(regex("^[a-z]+-", item.title))
  }
}

output "services_discovered" {
  value     = keys(local.services_discovered)
  sensitive = false
}

# Force refresh of data sources on every run
resource "random_id" "services_refresh_trigger" {
  byte_length = 8

  keepers = {
    timestamp = timestamp()
  }
}
