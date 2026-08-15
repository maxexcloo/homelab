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

resource "truenas_zvol" "virtual_machine_boot" {
  for_each = local.virtual_machines

  comments     = "${title(local.infrastructure.hosts[each.key].platform)} boot disk for ${local.infrastructure.hosts[each.key].fqdn}"
  compression  = "LZ4"
  name         = each.value.boot.zvol
  pool         = each.value.boot.pool
  volblocksize = "16K"
  volsize      = each.value.boot.size_gib * 1024 * 1024 * 1024

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_vm" "virtual_machine" {
  for_each = local.virtual_machines

  autostart             = true
  bootloader            = "UEFI"
  cores                 = each.value.cpu.cores
  cpu_mode              = "HOST-PASSTHROUGH"
  description           = "${title(local.infrastructure.hosts[each.key].platform)} node ${local.infrastructure.hosts[each.key].fqdn}"
  ensure_display_device = false
  memory                = each.value.memory_mib
  name                  = each.key
  threads               = each.value.cpu.threads
  time                  = "UTC"
  vcpus                 = each.value.cpu.sockets

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_vm_device" "virtual_machine" {
  for_each = local.virtual_machine_devices

  attributes = each.value.attributes
  dtype      = each.value.dtype
  order      = each.value.order
  vm         = tonumber(truenas_vm.virtual_machine[each.value.virtual_machine].id)
}

moved {
  from = truenas_zvol.taco_boot
  to   = truenas_zvol.virtual_machine_boot["taco"]
}

moved {
  from = truenas_vm.taco
  to   = truenas_vm.virtual_machine["taco"]
}

moved {
  from = truenas_vm_device.taco["boot"]
  to   = truenas_vm_device.virtual_machine["taco/boot"]
}

moved {
  from = truenas_vm_device.taco["cdrom"]
  to   = truenas_vm_device.virtual_machine["taco/cdrom"]
}

moved {
  from = truenas_vm_device.taco["network"]
  to   = truenas_vm_device.virtual_machine["taco/network"]
}
