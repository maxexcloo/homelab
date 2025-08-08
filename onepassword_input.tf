data "external" "onepassword_vault_homelab" {
  program = ["sh", "-c", "op item list --format=json --vault='${var.onepassword_vault_homelab}' | jq -c '{stdout: (. | tostring)}'"]
}

data "external" "onepassword_vault_services" {
  program = ["sh", "-c", "op item list --format=json --vault='${var.onepassword_vault_services}' | jq -c '{stdout: (. | tostring)}'"]
}

data "onepassword_item" "homelab" {
  for_each = local.onepassword_vault_homelab

  title = each.key
  vault = data.onepassword_vault.homelab.uuid
}

data "onepassword_item" "services" {
  for_each = local.onepassword_vault_services

  title = each.key
  vault = data.onepassword_vault.services.uuid
}

data "onepassword_vault" "homelab" {
  name = var.onepassword_vault_homelab
}

data "onepassword_vault" "services" {
  name = var.onepassword_vault_services
}

import {
  for_each = local.onepassword_vault_homelab

  id = "vaults/${data.onepassword_vault.homelab.uuid}/items/${each.value.id}"
  to = onepassword_item.homelab[each.key]
}

import {
  for_each = local.onepassword_vault_services

  id = "vaults/${data.onepassword_vault.services.uuid}/items/${each.value.id}"
  to = onepassword_item.services[each.key]
}

locals {
  # Parse homelab vault items (unified logic for routers and servers)
  onepassword_vault_homelab = {
    for item in jsondecode(data.external.onepassword_vault_homelab.result.stdout) :
    item.title => {
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

  # Parse services vault items
  onepassword_vault_services = {
    for item in jsondecode(data.external.onepassword_vault_services.result.stdout) :
    item.title => {
      id       = item.id
      name     = replace(item.title, "/^[^-]*-/", "")
      platform = split("-", item.title)[0]
    } if can(regex("^[a-z]+-", item.title))
  }
}

output "onepassword_discovered" {
  value = {
    homelab  = keys(local.onepassword_vault_homelab)
    services = keys(local.onepassword_vault_services)
  }

  sensitive = false
}