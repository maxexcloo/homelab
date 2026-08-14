data "truenas_network_interface" "services_physical" {
  id = local.truenas_service_nic.name
}

resource "truenas_network_interface" "services_physical" {
  aliases   = []
  ipv4_dhcp = false
  ipv6_auto = false
  name      = local.truenas_service_nic.name
  rollback  = true
  type      = "PHYSICAL"

  lifecycle {
    prevent_destroy = true

    precondition {
      condition = (
        data.truenas_network_interface.services_physical.type == "PHYSICAL" &&
        data.truenas_network_interface.services_physical.ipv4_dhcp == false &&
        (
          length(data.truenas_network_interface.services_physical.aliases) == 0 ||
          try(
            length(data.truenas_network_interface.services_physical.aliases) == 1 &&
            one(data.truenas_network_interface.services_physical.aliases).type == "INET" &&
            one(data.truenas_network_interface.services_physical.aliases).address == local.truenas_service_nic.address &&
            one(data.truenas_network_interface.services_physical.aliases).netmask == local.truenas_service_nic.prefix_length,
            false,
          )
        )
      )
      error_message = "The live Services NIC must be a static physical interface holding the expected IPv4 address before bridge adoption, or no address after adoption."
    }
  }
}

resource "truenas_network_interface" "services_bridge" {
  aliases = [
    {
      address = local.truenas_service_nic.address
      netmask = local.truenas_service_nic.prefix_length
      type    = "INET"
    },
  ]
  bridge_members = [truenas_network_interface.services_physical.name]
  ipv4_dhcp      = false
  ipv6_auto      = false
  name           = local.truenas_service_nic.bridge
  rollback       = true
  type           = "BRIDGE"

  lifecycle {
    prevent_destroy = true
  }
}
