locals {
  infrastructure      = yamldecode(file("${path.module}/data/infrastructure.yaml"))
  home_network        = local.infrastructure.networks.mbk
  truenas_service_nic = local.home_network.interfaces.services
  virtual_machines    = local.infrastructure.virtual_machines

  virtual_machine_devices = merge([
    for virtual_machine_name, virtual_machine in local.virtual_machines : {
      "${virtual_machine_name}/boot" = {
        attributes = {
          path = "/dev/zvol/${truenas_zvol.virtual_machine_boot[virtual_machine_name].id}"
          type = "VIRTIO"
        }
        dtype           = "DISK"
        order           = 1000
        virtual_machine = virtual_machine_name
      }
      "${virtual_machine_name}/cdrom" = {
        attributes = {
          path = virtual_machine.boot.iso_path
        }
        dtype           = "CDROM"
        order           = 1001
        virtual_machine = virtual_machine_name
      }
      "${virtual_machine_name}/network" = {
        attributes = {
          mac = virtual_machine.network.mac_address
          nic_attach = (
            local.infrastructure.networks[
              local.infrastructure.hosts[virtual_machine_name].location
            ].interfaces[virtual_machine.network.interface].bridge
          )
          type = "VIRTIO"
        }
        dtype           = "NIC"
        order           = 1002
        virtual_machine = virtual_machine_name
      }
    }
  ]...)
}
