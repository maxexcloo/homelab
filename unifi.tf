data "unifi_firewall_zone" "configured" {
  for_each = local.provider_settings.providers.unifi.firewall_zones

  name = each.value
}

locals {
  unifi_clients = {
    for interface in local.machine_interface_assignments : interface.mac => {
      fixed_ip = interface.address != null ? interface.address : ""
      hostname = interface.primary ? local.machine_fqdns[interface.machine] : null
      mac      = interface.mac
      name     = local.machine_hostnames[interface.machine]
    }
  }
}

resource "unifi_client" "host" {
  for_each = local.unifi_clients

  allow_existing         = true
  fixed_ip               = each.value.fixed_ip
  local_dns_record       = each.value.hostname != null ? each.value.hostname : ""
  mac                    = each.value.mac
  name                   = each.value.name
  note                   = local.managed_comment
  skip_forget_on_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "unifi_client" "talos_container" {
  for_each = local.truenas_talos_containers

  allow_existing   = true
  fixed_ip         = each.value.address
  local_dns_record = "${each.value.device_name}.${local.machines[each.key].network}.${local.domains.infrastructure}"
  mac              = each.value.mac
  name             = each.value.device_name
  note             = local.managed_comment
}

resource "unifi_firewall_policy" "configured" {
  for_each = local.provider_settings.providers.unifi.firewall_policies

  action  = each.value.action
  enabled = each.value.enabled
  name    = each.value.name

  source = {
    matching_target = each.value.source.matching_target
    zone_id         = data.unifi_firewall_zone.configured[each.value.source.zone].id
  }

  destination = merge(
    {
      matching_target = each.value.destination.matching_target
      zone_id         = data.unifi_firewall_zone.configured[each.value.destination.zone].id
    },
    can(each.value.destination.machines) ? { ips = [for machine in each.value.destination.machines : local.machine_private_ipv4_addresses[machine]] } : {},
  )

  lifecycle {
    prevent_destroy = true
  }
}

resource "unifi_setting" "site" {
  site = "default"

  # IDS is managed in the UniFi UI: this provider version's ips block does not
  # update the controller's threat-management settings.
  mgmt = {
    auto_upgrade = {
      enabled = true
      hour    = 3
    }

    # Leave SSH enabled and its keys unmanaged; the provider preserves omitted fields.
    ssh = {
      auth_password_enabled = false
    }
  }
}
