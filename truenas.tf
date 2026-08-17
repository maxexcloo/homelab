data "truenas_network_interface" "services_physical" {
  id = local.truenas_service_nic.name
}

locals {
  truenas_home_network = local.networks[local.truenas_host_machine.network]

  truenas_host = one(distinct([for virtual_machine in values(local.truenas_virtual_machines) : virtual_machine.host]))

  truenas_host_machine = local.machines[local.truenas_host]

  truenas_service_nic = local.truenas_home_network.interfaces.services

  truenas_datasets = merge([
    for target, storage in local.storage.targets : {
      for name, dataset in storage.datasets : "${target}/${name}" => merge(dataset, {
        name   = name
        target = target
      })
    }
  ]...)

  truenas_nfs_shares = merge([
    for target, storage in local.storage.targets : {
      for name, share in storage.nfs_shares : "${target}/${name}" => merge(share, {
        dataset_key = "${target}/${share.dataset}"
        name        = name
        networks = [
          for share_network in share.networks : cidrsubnet(
            local.networks[share_network.network].unifi.networks[share_network.vlan].subnet,
            0,
            0,
          )
        ]
        target = target
      })
    }
  ]...)

  truenas_snapshot_tasks = merge([
    for target, storage in local.storage.targets : {
      for name, task in storage.snapshot_tasks : "${target}/${name}" => merge(task, {
        name   = name
        target = target
      })
    }
  ]...)

  truenas_virtual_machine_devices = merge([
    for virtual_machine_name, virtual_machine in local.truenas_virtual_machines : {
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
          path = join("/", [
            trimsuffix(virtual_machine.boot.iso_directory, "/"),
            "talos-${local.talos_schematic_ids[local.machines[virtual_machine_name].cluster]}-${local.clusters[local.machines[virtual_machine_name].cluster].talos_version}.iso",
          ])
        }
        dtype           = "CDROM"
        order           = 1001
        virtual_machine = virtual_machine_name
      }
      "${virtual_machine_name}/network" = {
        attributes = {
          mac = local.machines[virtual_machine_name].mac_address
          nic_attach = local.networks[
            local.machines[virtual_machine_name].network
          ].interfaces[local.machines[virtual_machine_name].vlan].bridge
          type = "VIRTIO"
        }
        dtype           = "NIC"
        order           = 1002
        virtual_machine = virtual_machine_name
      }
    }
  ]...)

  truenas_virtual_machines = {
    for name, machine in local.machines : name => machine
    if try(machine.provider, null) == "truenas"
  }
}

resource "terraform_data" "truenas_storage_target" {
  for_each = local.storage.targets

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
  bridge_members = [truenas_network_interface.services_physical.name]
  ipv4_dhcp      = false
  ipv6_auto      = false
  name           = local.truenas_service_nic.bridge
  rollback       = true
  type           = "BRIDGE"

  aliases = [
    {
      address = local.truenas_service_nic.address
      netmask = local.truenas_service_nic.prefix_length
      type    = "INET"
    },
  ]

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
  for_each = local.truenas_virtual_machines

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
  for_each = local.truenas_virtual_machine_devices

  attributes = each.value.attributes
  dtype      = each.value.dtype
  order      = each.value.order
  vm         = tonumber(truenas_vm.virtual_machine[each.value.virtual_machine].id)
}

resource "truenas_zvol" "virtual_machine_boot" {
  for_each = local.truenas_virtual_machines

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
