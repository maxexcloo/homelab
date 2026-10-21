data "unifi_network" "configured" {
  for_each = local.unifi_networks

  name = each.value.name
}

locals {
  unifi_clients = {
    for interface in local.machine_interface_assignments : interface.mac => {
      fixed_ip    = interface.bridge == null ? interface.address : null
      hostname    = interface.primary ? local.machine_fqdns[interface.machine] : null
      ipv6        = interface.ipv6
      mac         = interface.mac
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
  local_dns_record       = each.value.hostname != null ? each.value.hostname : ""
  mac                    = each.value.mac
  name                   = each.value.hostname != null ? each.value.name : null
  network_id             = local.unifi_networks[each.value.network_key].vlan != null ? data.unifi_network.configured[each.value.network_key].id : null
  note                   = local.managed_comment
  skip_forget_on_destroy = false

  depends_on = [terraform_data.unifi_network_validation]

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
  note             = "Talos Kubernetes Node"

  lifecycle {
    prevent_destroy = true
  }
}

resource "unifi_dns_record" "host_ipv6" {
  for_each = { for mac, client in local.unifi_clients : mac => client if client.hostname != null }

  # Client DNS records only override A; missing AAAA queries otherwise reach
  # public Tailscale DNS. Use native IPv6 when configured, or an unusable target
  # for this IPv4-only local name, without changing public DNS or LAN IPv6.
  name        = each.value.hostname
  record_type = "AAAA"
  value       = each.value.ipv6 != null ? each.value.ipv6 : "::"
}
