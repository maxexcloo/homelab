locals {
  unifi_networks = merge([
    for location, network in local.networks : {
      for network_key, network_config in try(network.unifi.networks, {}) :
      "${location}/${network_key}" => {
        location = location
        name     = network_config.name
        subnet   = network_config.subnet
        vlan     = try(network_config.vlan, null)
      }
    }
  ]...)

  unifi_clients = {
    for name, machine in local.machines : name => {
      fixed_ip         = machine.address
      local_dns_record = local.machine_fqdns[name]
      mac              = machine.mac_address
      network_key      = "${machine.location}/${machine.network}"
    }
    if try(machine.mac_address, null) != null && try(machine.address, null) != null
  }
}

data "unifi_network" "default" {
  for_each = local.unifi_networks

  name = each.value.name
}

resource "terraform_data" "unifi_network_validation" {
  for_each = local.unifi_networks

  input = data.unifi_network.default[each.key].id

  lifecycle {
    precondition {
      condition     = data.unifi_network.default[each.key].enabled
      error_message = "UniFi network ${each.value.name} is disabled."
    }

    precondition {
      condition     = data.unifi_network.default[each.key].subnet == each.value.subnet
      error_message = "UniFi network ${each.value.name} does not use the expected subnet ${each.value.subnet}."
    }

    precondition {
      condition     = each.value.vlan == null ? data.unifi_network.default[each.key].vlan == null : data.unifi_network.default[each.key].vlan == each.value.vlan
      error_message = "UniFi network ${each.value.name} does not use the expected VLAN."
    }
  }
}

resource "unifi_client" "host" {
  for_each = local.unifi_clients

  allow_existing         = true
  fixed_ip               = each.value.fixed_ip
  local_dns_record       = each.value.local_dns_record
  mac                    = each.value.mac
  name                   = each.key
  network_id             = local.unifi_networks[each.value.network_key].vlan != null ? data.unifi_network.default[each.value.network_key].id : null
  note                   = "Managed by OpenTofu"
  skip_forget_on_destroy = false

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [terraform_data.unifi_network_validation]
}
