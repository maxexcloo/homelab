data "external" "onepassword_vault_homelab_all" {
  program = ["sh", "-c", "op item list --format=json --vault='${var.onepassword_vault_homelab}' | jq -c '{stdout: (. | tostring)}'"]
}

data "external" "onepassword_vault_services_all" {
  program = ["sh", "-c", "op item list --format=json --vault='${var.onepassword_vault_services}' | jq -c '{stdout: (. | tostring)}'"]
}

data "onepassword_vault" "homelab" {
  name = var.onepassword_vault_homelab
}

data "onepassword_vault" "services" {
  name = var.onepassword_vault_services
}

locals {
  onepassword_vault_homelab_all = merge(
    local.onepassword_vault_homelab_routers,
    local.onepassword_vault_homelab_servers
  )

  onepassword_vault_homelab_routers = {
    for item in jsondecode(data.external.onepassword_vault_homelab_all.result.stdout) : item.title => {
      fqdn     = "${split("-", item.title)[1]}"
      id       = item.id
      name     = replace(item.title, "/^[a-z]+-[a-z]+-/", "")
      platform = split("-", item.title)[0]
      region   = split("-", item.title)[1]
      title    = replace(item.title, "/^[a-z]+-/", "")
    } if can(regex("^[a-z]+-[a-z]+", item.title))
  }

  onepassword_vault_homelab_servers = {
    for item in jsondecode(data.external.onepassword_vault_homelab_all.result.stdout) : item.title => {
      fqdn     = "${replace(item.title, "/^[a-z]+-[a-z]+-/", "")}.${split("-", item.title)[1]}"
      id       = item.id
      name     = replace(item.title, "/^[a-z]+-[a-z]+-/", "")
      platform = split("-", item.title)[0]
      region   = split("-", item.title)[1]
      title    = replace(item.title, "/^[a-z]+-[a-z]+-/", "")
    } if can(regex("^[a-z]+-[a-z]+-", item.title))
  }

  onepassword_vault_services_all = {
    for item in jsondecode(data.external.onepassword_vault_services_all.result.stdout) : item.title => {
      id       = item.id
      name     = replace(item.title, "/^[^-]*-/", "")
      platform = split("-", item.title)[0]
    } if can(regex("^[a-z]+-", item.title))
  }
}

output "onepassword_discovered" {
  value = {
    homelab  = keys(local.onepassword_vault_homelab_all)
    services = keys(local.onepassword_vault_services_all)
  }

  sensitive = false
}

data "onepassword_item" "homelab" {
  for_each = local.onepassword_vault_homelab_all

  title = each.key
  vault = data.onepassword_vault.homelab.uuid
}

data "onepassword_item" "services" {
  for_each = local.onepassword_vault_services_all

  title = each.key
  vault = data.onepassword_vault.services.uuid
}

import {
  for_each = local.onepassword_vault_homelab_all

  id = "vaults/${data.onepassword_vault.homelab.uuid}/items/${each.value.id}"
  to = onepassword_item.homelab[each.key]
}

import {
  for_each = local.onepassword_vault_services_all

  id = "vaults/${data.onepassword_vault.services.uuid}/items/${each.value.id}"
  to = onepassword_item.services[each.key]
}

resource "onepassword_item" "homelab" {
  for_each = local.onepassword_vault_homelab_all

  title    = data.onepassword_item.homelab[each.key].title
  url      = "${each.value.fqdn}.${var.domain_internal}"
  username = data.onepassword_item.homelab[each.key].username
  vault    = data.onepassword_vault.homelab.uuid
}

resource "onepassword_item" "services" {
  for_each = local.onepassword_vault_services_all

  title    = data.onepassword_item.services[each.key].title
  username = data.onepassword_item.services[each.key].username
  vault    = data.onepassword_vault.services.uuid
}
