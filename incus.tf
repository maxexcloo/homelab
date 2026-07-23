locals {
  _incus_vms = {
    for server_key, server in local.incus_vm_requests : server_key => server
    if(
      server.parent != "" &&
      can(local.incus_servers[server.parent])
    )
  }

  incus_servers = {
    for server_key, server in local.servers_model : server_key => server
    if(
      server.platform == "incus" &&
      server.type == "server" &&
      server.networking.management_host != ""
    )
  }

  # Requested Incus VMs are kept separate so validation can report invalid
  # parents without making those requests part of resource membership.
  incus_vm_requests = {
    for server_key, server in local.servers_model : server_key => server
    if(
      server.platform == "incus" &&
      server.type == "vm"
    )
  }
}

resource "incus_instance" "vm" {
  for_each = local._incus_vms

  description = each.value.identity.description
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
      "user.user-data"      = base64encode(local.bootstrap_cloud_config[each.key])
    } : {},
    each.value.platform_config.incus.type == "virtual-machine" ? {
      "security.secureboot" = each.value.platform_config.incus.secureboot
    } : {}
  )

  dynamic "device" {
    for_each = each.value.platform_config.incus.disks

    content {
      name = device.value.name
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
      name = device.value.name
      type = "nic"

      properties = merge(
        {
          network = device.value.network
        },
        try(device.value.mac_address, "") != "" ? {
          hwaddr = device.value.mac_address
        } : {}
      )
    }
  }

  dynamic "device" {
    for_each = each.value.platform_config.incus.pci_devices

    content {
      name = device.value.name
      type = "pci"

      properties = {
        address = device.value.address
      }
    }
  }

  dynamic "device" {
    for_each = each.value.platform_config.incus.usb_devices

    content {
      name = device.value.name
      type = "usb"

      properties = merge(
        {
          productid = device.value.productid
          vendorid  = device.value.vendorid
        },
        try(device.value.mode, "") != "" ? {
          mode = device.value.mode
        } : {}
      )
    }
  }

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      config["user.user-data"]
    ]
  }
}
