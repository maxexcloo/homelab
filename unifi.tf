data "unifi_network" "configured" {
  for_each = local.unifi_networks

  name = each.value.name
}

locals {
  unifi_clients = {
    for interface in local.machine_interface_assignments : interface.client_mac => {
      fixed_ip    = interface.address
      hostname    = interface.primary ? local.machine_fqdns[interface.machine] : null
      mac         = interface.client_mac
      name        = local.machine_hostnames[interface.machine]
      network_key = "${interface.network}/${interface.subnet}"
    }
    if interface.address != null
  }

  unifi_networks = merge([
    for network, site in local.networks : {
      for subnet, subnet_config in try(site.subnets, {}) :
      "${network}/${subnet}" => {
        name   = subnet_config.name
        subnet = subnet_config.cidr
        vlan   = try(subnet_config.vlan, null)
      }
    }
  ]...)
}

resource "unifi_client" "host" {
  for_each = local.unifi_clients

  allow_existing         = true
  fixed_ip               = each.value.fixed_ip
  local_dns_record       = each.value.hostname != null ? each.value.hostname : ""
  mac                    = each.value.mac
  name                   = each.value.hostname != null ? each.value.name : null
  network_id             = local.unifi_networks[each.value.network_key].vlan != null ? data.unifi_network.configured[each.value.network_key].id : null
  note                   = local.managed_comment
  skip_forget_on_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "unifi_client" "talos_container" {
  allow_existing   = true
  fixed_ip         = local.truenas_talos_container.address
  local_dns_record = "${local.truenas_talos_container.app_name}.${local.machines[local.truenas_talos_container_host].network}.${local.domains.infrastructure}"
  mac              = local.truenas_talos_container.mac
  name             = local.truenas_talos_container.app_name
  network_id       = data.unifi_network.configured[local.truenas_talos_container_network_key].id
  note             = local.managed_comment

  lifecycle {
    prevent_destroy = true
  }
}
