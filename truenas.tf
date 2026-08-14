resource "truenas_network_interface" "services_physical" {
  aliases   = []
  ipv4_dhcp = false
  ipv6_auto = false
  name      = local.truenas_service_nic.name
  rollback  = true
  type      = "PHYSICAL"

  lifecycle {
    prevent_destroy = true
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
