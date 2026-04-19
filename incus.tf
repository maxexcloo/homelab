locals {
  # Incus remotes are configured only for parent servers with a reachable API.
  incus_servers = {
    for k, v in local.servers_desired : k => v
    if v.platform == "incus" && v.type == "server" && v.networking.management_address != ""
  }

  # Incus instances are child VMs/containers whose parent remote is configured above.
  incus_vms = {
    for k, v in local.servers_desired : k => v
    if v.parent != "" && v.platform == "incus" && v.type == "vm" && v.platform_config.incus != null && contains(keys(local.incus_servers), v.parent)
  }
}

resource "incus_instance" "vm" {
  for_each = local.incus_vms

  description = each.value.description
  image       = each.value.platform_config.incus.image
  name        = each.value.identity.name
  profiles    = each.value.platform_config.incus.profiles
  project     = "default"
  remote      = each.value.parent
  type        = each.value.platform_config.incus.type

  config = merge(
    {
      "limits.cpu"                 = each.value.platform_config.incus.cpus
      "limits.memory"              = "${each.value.platform_config.incus.memory}GiB"
      "security.protection.delete" = each.value.platform_config.incus.protection
    },
    each.value.platform_config.incus.type == "container" ? {
      "security.nesting"    = each.value.platform_config.incus.nested
      "security.privileged" = each.value.platform_config.incus.privileged
      "user.user-data"      = base64encode(local.cloud_config[each.key])
    } : {},
    each.value.platform_config.incus.type == "virtual-machine" ? {
      "security.secureboot" = each.value.platform_config.incus.secureboot
    } : {}
  )

  dynamic "device" {
    for_each = each.value.platform_config.incus.disks

    content {
      name = device.value.name != "" ? device.value.name : "disk-${device.key + 1}"
      type = "disk"

      properties = {
        path = device.value.path
        pool = device.value.pool
        size = "${device.value.size}GiB"
      }
    }
  }

  dynamic "device" {
    for_each = each.value.platform_config.incus.networks

    content {
      name = device.value.name != "" ? device.value.name : "eth-${device.key + 1}"
      type = "nic"

      properties = merge(
        {
          network = device.value.network
        },
        device.value.mac_address != "" ? {
          hwaddr = device.value.mac_address
        } : {}
      )
    }
  }

  dynamic "device" {
    for_each = each.value.platform_config.incus.pci_devices

    content {
      name = device.value.name != "" ? device.value.name : "pci-${device.key + 1}"
      type = "pci"

      properties = {
        address = device.value.address
      }
    }
  }

  dynamic "device" {
    for_each = each.value.platform_config.incus.usb_devices

    content {
      name = device.value.name != "" ? device.value.name : "usb-${device.key + 1}"
      type = "usb"

      properties = merge(
        {
          productid = device.value.productid
          vendorid  = device.value.vendorid
        },
        device.value.mode != "" ? {
          mode = device.value.mode
        } : {}
      )
    }
  }

  lifecycle {
    ignore_changes = [
      config["user.user-data"]
    ]
  }
}
