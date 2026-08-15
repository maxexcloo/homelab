locals {
  infrastructure      = yamldecode(file("${path.module}/data/infrastructure.yaml"))
  home_network        = local.infrastructure.networks.mbk
  taco                = local.infrastructure.virtual_machines.taco
  truenas_service_nic = local.home_network.interfaces.services

  taco_devices = {
    boot = {
      attributes = {
        path = "/dev/zvol/${truenas_zvol.taco_boot.id}"
        type = "VIRTIO"
      }
      dtype = "DISK"
      order = 1000
    }
    cdrom = {
      attributes = {
        path = local.taco.boot.iso_path
      }
      dtype = "CDROM"
      order = 1001
    }
    network = {
      attributes = {
        mac        = local.taco.mac_address
        nic_attach = truenas_network_interface.services_bridge.name
        type       = "VIRTIO"
      }
      dtype = "NIC"
      order = 1002
    }
  }
}
