data "unifi_network" "configured" {
  for_each = local.unifi_networks

  name = each.value.name
}

locals {
  unifi_clients = {
    for name, machine in local.machines : name => {
      fixed_ip    = machine.address
      mac         = machine.mac_address
      network_key = "${machine.network}/${machine.vlan}"
    }
    if try(machine.mac_address, null) != null && try(machine.address, null) != null
  }

  unifi_networks = merge([
    for network, site in local.networks : {
      for network_key, network_config in try(site.unifi.networks, {}) :
      "${network}/${network_key}" => {
        name   = network_config.name
        subnet = network_config.subnet
        vlan   = try(network_config.vlan, null)
      }
    }
  ]...)
}

resource "terraform_data" "unifi_network_validation" {
  for_each = local.unifi_networks

  input = data.unifi_network.configured[each.key].id

  lifecycle {
    precondition {
      condition     = data.unifi_network.configured[each.key].enabled
      error_message = "UniFi network ${each.value.name} is disabled."
    }

    precondition {
      condition     = data.unifi_network.configured[each.key].subnet == each.value.subnet
      error_message = "UniFi network ${each.value.name} does not use the expected subnet ${each.value.subnet}."
    }

    precondition {
      condition     = each.value.vlan == null ? data.unifi_network.configured[each.key].vlan == null : data.unifi_network.configured[each.key].vlan == each.value.vlan
      error_message = "UniFi network ${each.value.name} does not use the expected VLAN."
    }
  }
}

resource "unifi_client" "host" {
  for_each = local.unifi_clients

  allow_existing         = true
  fixed_ip               = each.value.fixed_ip
  mac                    = each.value.mac
  name                   = each.key
  network_id             = local.unifi_networks[each.value.network_key].vlan != null ? data.unifi_network.configured[each.value.network_key].id : null
  note                   = "Managed by OpenTofu"
  skip_forget_on_destroy = false

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [terraform_data.unifi_network_validation]
}
