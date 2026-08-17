data "truenas_network_interface" "services_physical" {
  id = local.truenas_service_nic.name
}

resource "terraform_data" "truenas_storage_target" {
  for_each = local.truenas_storage_targets

  input = each.key

  lifecycle {
    precondition {
      condition     = each.key == local.truenas_host
      error_message = "The storage target must match the TrueNAS compute host configured for this root."
    }

    precondition {
      condition     = try(local.machines[each.key].platform, null) == "truenas"
      error_message = "The storage target must reference a TrueNAS machine."
    }
  }
}

resource "truenas_dataset" "managed" {
  for_each = local.truenas_datasets

  atime         = each.value.atime
  comments      = "Kubernetes persistent storage managed by OpenTofu"
  compression   = each.value.compression
  deduplication = "OFF"
  name          = each.value.name
  pool          = each.value.pool
  readonly      = "OFF"
  record_size   = each.value.record_size
  share_type    = "GENERIC"
  sync          = "STANDARD"

  depends_on = [terraform_data.truenas_storage_target]

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

resource "truenas_share_nfs" "managed" {
  for_each = local.truenas_nfs_shares

  comment       = "Kubernetes persistent storage managed by OpenTofu"
  enabled       = true
  maproot_group = "wheel"
  maproot_user  = "root"
  networks      = each.value.networks
  path          = truenas_dataset.managed[each.value.dataset_key].mount_point
  readonly      = false
  security      = ["SYS"]

  depends_on = [terraform_data.truenas_storage_target]

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_snapshot_task" "managed" {
  for_each = local.truenas_snapshot_tasks

  allow_empty     = true
  dataset         = each.value.dataset
  enabled         = true
  lifetime_unit   = each.value.lifetime.unit
  lifetime_value  = each.value.lifetime.value
  naming_schema   = each.value.naming_schema
  recursive       = true
  schedule_dom    = each.value.schedule.day_of_month
  schedule_dow    = each.value.schedule.day_of_week
  schedule_hour   = each.value.schedule.hour
  schedule_minute = each.value.schedule.minute
  schedule_month  = each.value.schedule.month

  depends_on = [terraform_data.truenas_storage_target]

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_vm" "virtual_machine" {
  for_each = local.virtual_machines

  autostart             = true
  bootloader            = "UEFI"
  cores                 = each.value.compute.cores
  cpu_mode              = "HOST-PASSTHROUGH"
  description           = "${title(local.machines[each.key].platform)} node ${local.machine_fqdns[each.key]}"
  ensure_display_device = false
  memory                = each.value.compute.memory_mib
  name                  = each.key
  threads               = each.value.compute.threads
  time                  = "UTC"
  vcpus                 = each.value.compute.sockets

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = try(local.machines[local.truenas_host].platform == "truenas", false)
      error_message = "The configured TrueNAS compute host must reference a TrueNAS server."
    }

    precondition {
      condition     = contains(keys(local.machines), each.key)
      error_message = "Every TrueNAS virtual machine must reference a server with the same key."
    }
  }
}

resource "truenas_vm_device" "virtual_machine" {
  for_each = local.virtual_machine_devices

  attributes = each.value.attributes
  dtype      = each.value.dtype
  order      = each.value.order
  vm         = tonumber(truenas_vm.virtual_machine[each.value.virtual_machine].id)
}

resource "truenas_zvol" "virtual_machine_boot" {
  for_each = local.virtual_machines

  comments     = "${title(local.machines[each.key].platform)} boot disk for ${local.machine_fqdns[each.key]}"
  compression  = "LZ4"
  name         = "virtual-machines/${each.key}"
  pool         = each.value.boot.pool
  volblocksize = "16K"
  volsize      = each.value.boot.size_mib * 1024 * 1024

  lifecycle {
    prevent_destroy = true
  }
}
