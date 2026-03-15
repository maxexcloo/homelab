locals {
  incus_servers = {
    for k, v in local._servers : k => v
    if v.platform == "incus" && v.type == "server" && v.management_address != null && v.management_address != "" && v.management_port != null && v.management_port != ""
  }

  incus_vms = {
    for k, v in local._servers : k => v
    if v.platform == "incus" && v.type == "vm" && try(v.config.incus, null) != null && v.parent != null && v.parent != "" && contains(keys(local.incus_servers), v.parent)
  }
}

resource "incus_instance" "vm" {
  for_each = local.incus_vms

  image    = each.value.config.incus.image
  name     = each.value.name
  profiles = each.value.config.incus.profiles
  remote   = each.value.parent
  type     = each.value.config.incus.type

  config = merge(
    {
      "limits.cpu"          = each.value.config.incus.cpus
      "limits.memory"       = "${each.value.config.incus.memory}GiB"
      "security.secureboot" = each.value.config.incus.secureboot
      "user.user-data"      = base64encode(local.cloud_config[each.key])
    },
    # Container-specific settings
    each.value.config.incus.type == "container" ? {
      "security.nesting"    = each.value.config.incus.nested
      "security.privileged" = each.value.config.incus.privileged
    } : {}
  )

  dynamic "device" {
    for_each = each.value.config.incus.disks

    content {
      name = try(device.value.name, null) != null ? device.value.name : "disk-${device.key}"
      type = "disk"

      properties = {
        path = device.value.path
        pool = device.value.pool
        size = "${device.value.size}GiB"
      }
    }
  }

  dynamic "device" {
    for_each = each.value.config.incus.networks

    content {
      name = try(device.value.name, null) != null ? device.value.name : "eth${device.key}"
      type = "nic"

      properties = merge(
        {
          name    = try(device.value.name, null) != null ? device.value.name : "eth${device.key}"
          network = device.value.network
        },
        try(device.value.mac_address, null) != null ? {
          hwaddr = device.value.mac_address
        } : {}
      )
    }
  }

  dynamic "device" {
    for_each = each.value.config.incus.pci_devices

    content {
      name = try(device.value.name, null) != null ? device.value.name : "pci-${device.key}"
      type = "pci"

      properties = {
        address = device.value.address
      }
    }
  }

  dynamic "device" {
    for_each = each.value.config.incus.usb_devices

    content {
      name = try(device.value.name, null) != null ? device.value.name : "usb-${device.key}"
      type = "usb"

      properties = merge(
        {
          vendorid  = device.value.vendorid
          productid = device.value.productid
        },
        try(device.value.mode, null) != null ? {
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
