locals {
  incus_profiles = {
    for name, profile in {
      for filepath in fileset(path.module, "data/incus/profiles/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : name => provider::deepmerge::merge(local.defaults.incus.profiles, profile)
  }

  incus_profile_remotes = merge([
    for profile_name, profile in local.incus_profiles : {
      for remote in profile.remotes : "${profile_name}:${remote}" => {
        name    = profile_name
        profile = profile
        remote  = remote
      }
      if contains(keys(local.incus_servers), remote)
    }
  ]...)

  incus_projects = {
    for name, project in {
      for filepath in fileset(path.module, "data/incus/projects/*.yml") :
      trimsuffix(basename(filepath), ".yml") => yamldecode(file("${path.module}/${filepath}"))
    } : name => provider::deepmerge::merge(local.defaults.incus.projects, project)
  }

  incus_project_remotes = merge([
    for project_name, project in local.incus_projects : {
      for remote in project.remotes : "${project_name}:${remote}" => {
        name    = project_name
        project = project
        remote  = remote
      }
      if contains(keys(local.incus_servers), remote)
    }
  ]...)

  incus_servers = {
    for k, v in local.servers : k => v
    if v.identity.type == "server" && v.platform == "incus" && v.networking.management_address != "" && v.networking.management_port != 0
  }

  incus_vms = {
    for k, v in local.servers : k => v
    if v.identity.parent != "" && v.identity.type == "vm" && v.platform == "incus" && v.platform_config.incus != null && contains(keys(local.incus_servers), v.identity.parent)
  }
}

resource "incus_profile" "profile" {
  for_each = local.incus_profile_remotes

  config = each.value.profile.config
  name   = each.value.name
  remote = each.value.remote

  dynamic "device" {
    for_each = each.value.profile.devices

    content {
      name = device.key
      type = device.value.type

      properties = {
        for k, v in device.value : k => v
        if k != "type" && k != "name"
      }
    }
  }
}

resource "incus_project" "project" {
  for_each = local.incus_project_remotes

  config      = each.value.project.config
  description = each.value.project.description
  name        = each.value.name
  remote      = each.value.remote
}

resource "incus_instance" "vm" {
  for_each = local.incus_vms

  description = each.value.description
  image       = each.value.platform_config.incus.image
  name        = each.value.identity.name
  profiles    = each.value.platform_config.incus.profiles
  project     = "default"
  remote      = each.value.identity.parent
  type        = each.value.features.talos ? "virtual-machine" : each.value.platform_config.incus.type

  config = merge(
    {
      "limits.cpu"                 = each.value.platform_config.incus.cpus
      "limits.memory"              = "${each.value.platform_config.incus.memory}GiB"
      "security.protection.delete" = each.value.platform_config.incus.protection
    },
    each.value.platform_config.incus.type == "container" && !each.value.features.talos ? {
      "security.nesting"    = each.value.platform_config.incus.nested
      "security.privileged" = each.value.platform_config.incus.privileged
      "user.user-data"      = base64encode(local.cloud_config[each.key])
    } : {},
    each.value.platform_config.incus.type == "virtual-machine" || each.value.features.talos ? {
      "security.secureboot" = each.value.features.talos ? false : each.value.platform_config.incus.secureboot
    } : {}
  )

  dynamic "device" {
    for_each = each.value.platform_config.incus.disks

    content {
      name = device.value.name != "" ? device.value.name : "disk-${device.key}"
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
      name = device.value.name != "" ? device.value.name : "eth${device.key}"
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
      name = device.value.name != "" ? device.value.name : "pci-${device.key}"
      type = "pci"

      properties = {
        address = device.value.address
      }
    }
  }

  dynamic "device" {
    for_each = each.value.platform_config.incus.usb_devices

    content {
      name = device.value.name != "" ? device.value.name : "usb-${device.key}"
      type = "usb"

      properties = merge(
        {
          vendorid  = device.value.vendorid
          productid = device.value.productid
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
