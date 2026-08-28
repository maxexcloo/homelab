data "truenas_network_interface" "services_physical" {
  for_each = local.truenas_hosts_services

  id       = local.networks[each.value.network].interfaces.services.name
  provider = truenas.hosts[each.key]
}

locals {
  truenas_dataset_mount_points = merge(
    {
      for key, dataset in truenas_dataset.child : key => dataset.mount_point
    },
    {
      for key, dataset in truenas_dataset.root : key => dataset.mount_point
    },
  )

  truenas_datasets = merge([
    for target, storage in local.storage.truenas : {
      for name, dataset in storage.datasets : "${target}/${name}" => merge(dataset, {
        name               = name
        parent_dataset_key = try(dataset.parent_dataset, null) == null ? null : "${target}/${dataset.parent_dataset}"
        target             = target
      })
    }
  ]...)

  truenas_datasets_child = {
    for key, dataset in local.truenas_datasets : key => dataset
    if dataset.parent_dataset_key != null
  }

  truenas_datasets_root = {
    for key, dataset in local.truenas_datasets : key => dataset
    if dataset.parent_dataset_key == null
  }

  truenas_hosts = {
    for name, machine in local.machines : name => machine
    if machine.platform == "truenas"
  }

  truenas_hosts_services = {
    for name, machine in local.truenas_hosts : name => machine
    if try(local.networks[machine.network].interfaces.services, null) != null
  }

  truenas_shares_nfs = merge([
    for target, storage in local.storage.truenas : {
      for name, share in storage.nfs_shares : "${target}/${name}" => merge(share, {
        dataset_key = try(share.dataset, null) == null ? null : "${target}/${share.dataset}"
        name        = name
        path        = try(share.path, null)
        target      = target
        networks = [
          for share_network in share.networks : cidrsubnet(
            local.networks[share_network.network].unifi.networks[share_network.vlan].subnet,
            0,
            0,
          )
        ]
      })
    }
  ]...)

  truenas_virtual_machine_cdrom_devices = {
    for virtual_machine_name, virtual_machine in local.truenas_virtual_machines : "${virtual_machine_name}/cdrom" => {
      dtype           = "CDROM"
      order           = 1001
      virtual_machine = virtual_machine_name
      attributes = {
        path = join("/", [
          trimsuffix(virtual_machine.boot.iso_directory, "/"),
          "talos-${local.talos_image_factory_schematic_ids[local.machines[virtual_machine_name].cluster]}-${local.clusters[local.machines[virtual_machine_name].cluster].talos_version}.iso",
        ])
      }
    }
  }

  truenas_virtual_machine_devices = merge([
    for virtual_machine_name, virtual_machine in local.truenas_virtual_machines : {
      "${virtual_machine_name}/boot" = {
        dtype           = "DISK"
        order           = 1000
        virtual_machine = virtual_machine_name
        attributes = {
          path = "/dev/zvol/${truenas_zvol.virtual_machine_boot[virtual_machine_name].id}"
          type = "VIRTIO"
        }
      }
      "${virtual_machine_name}/network" = {
        dtype           = "NIC"
        order           = 1002
        virtual_machine = virtual_machine_name
        attributes = {
          mac = local.machines[virtual_machine_name].mac_address
          nic_attach = local.networks[
            local.machines[virtual_machine_name].network
          ].interfaces[local.machines[virtual_machine_name].vlan].bridge
          type = "VIRTIO"
        }
      }
    }
  ]...)

  truenas_virtual_machines = {
    for name, machine in local.machines : name => machine
    if try(machine.provider, null) == "truenas"
  }
}

resource "terraform_data" "truenas_storage_target" {
  for_each = local.storage.truenas

  input = each.key

  lifecycle {
    precondition {
      condition     = can(local.truenas_hosts[each.key])
      error_message = "Every TrueNAS storage configuration must reference an existing TrueNAS host."
    }

    precondition {
      condition = alltrue([
        for dataset in values(each.value.datasets) : try(dataset.parent_dataset, null) == null || try(
          can(each.value.datasets[dataset.parent_dataset]) &&
          try(each.value.datasets[dataset.parent_dataset].parent_dataset, null) == null &&
          each.value.datasets[dataset.parent_dataset].pool == dataset.pool,
          false,
        )
      ])
      error_message = "Every child dataset must reference an existing root dataset in the same pool."
    }

    precondition {
      condition = alltrue([
        for share in values(each.value.nfs_shares) : (try(share.dataset, null) == null) != (try(share.path, null) == null)
      ])
      error_message = "Every NFS share must reference exactly one managed dataset or existing path."
    }

    precondition {
      condition = alltrue([
        for share in values(each.value.nfs_shares) : try(share.dataset, null) == null || can(each.value.datasets[share.dataset])
      ])
      error_message = "Every NFS share dataset must exist on the same TrueNAS host."
    }

    precondition {
      condition = alltrue([
        for share in values(each.value.nfs_shares) : length(try(share.networks, [])) > 0
      ])
      error_message = "Every NFS share must declare at least one network."
    }

    precondition {
      condition = alltrue(flatten([
        for share in values(each.value.nfs_shares) : [
          for share_network in try(share.networks, []) : can(local.networks[share_network.network].unifi.networks[share_network.vlan])
        ]
      ]))
      error_message = "Every NFS share network must reference an existing UniFi network."
    }
  }
}

resource "truenas_dataset" "child" {
  for_each = local.truenas_datasets_child

  atime          = each.value.atime
  comments       = "Homelab OpenTofu Managed"
  compression    = each.value.compression
  deduplication  = "OFF"
  name           = each.value.name
  parent_dataset = truenas_dataset.root[each.value.parent_dataset_key].name
  pool           = each.value.pool
  provider       = truenas.hosts[each.value.target]
  readonly       = "OFF"
  record_size    = each.value.record_size
  share_type     = "GENERIC"
  sync           = "STANDARD"

  depends_on = [terraform_data.truenas_storage_target]

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_dataset" "root" {
  for_each = local.truenas_datasets_root

  atime         = each.value.atime
  comments      = "Homelab OpenTofu Managed"
  compression   = each.value.compression
  deduplication = "OFF"
  name          = each.value.name
  pool          = each.value.pool
  provider      = truenas.hosts[each.value.target]
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
  for_each = local.truenas_hosts_services

  bridge_members = [truenas_network_interface.services_physical[each.key].name]
  ipv4_dhcp      = false
  ipv6_auto      = false
  name           = local.networks[each.value.network].interfaces.services.bridge
  provider       = truenas.hosts[each.key]
  rollback       = true
  type           = "BRIDGE"

  aliases = [
    {
      address = local.networks[each.value.network].interfaces.services.address
      netmask = local.networks[each.value.network].interfaces.services.prefix_length
      type    = "INET"
    },
  ]

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_network_interface" "services_physical" {
  for_each = local.truenas_hosts_services

  aliases   = []
  ipv4_dhcp = false
  ipv6_auto = false
  name      = local.networks[each.value.network].interfaces.services.name
  provider  = truenas.hosts[each.key]
  rollback  = true
  type      = "PHYSICAL"

  lifecycle {
    prevent_destroy = true

    precondition {
      condition = (
        data.truenas_network_interface.services_physical[each.key].type == "PHYSICAL" &&
        data.truenas_network_interface.services_physical[each.key].ipv4_dhcp == false &&
        (
          length(data.truenas_network_interface.services_physical[each.key].aliases) == 0 ||
          try(
            length(data.truenas_network_interface.services_physical[each.key].aliases) == 1 &&
            one(data.truenas_network_interface.services_physical[each.key].aliases).type == "INET" &&
            one(data.truenas_network_interface.services_physical[each.key].aliases).address == local.networks[each.value.network].interfaces.services.address &&
            one(data.truenas_network_interface.services_physical[each.key].aliases).netmask == local.networks[each.value.network].interfaces.services.prefix_length,
            false,
          )
        )
      )
      error_message = "The live Services NIC on ${each.key} must be a static physical interface holding the expected IPv4 address before bridge adoption, or no address after adoption."
    }
  }
}

resource "truenas_service" "nfs" {
  for_each = {
    for target, storage in local.storage.truenas : target => storage
    if length(try(storage.nfs_shares, {})) > 0
  }

  enable   = true
  provider = truenas.hosts[each.key]
  service  = "nfs"

  depends_on = [truenas_share_nfs.managed]

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_share_nfs" "managed" {
  for_each = local.truenas_shares_nfs

  comment       = "Homelab OpenTofu Managed"
  enabled       = true
  maproot_group = "wheel"
  maproot_user  = "root"
  networks      = each.value.networks
  path          = each.value.dataset_key == null ? each.value.path : try(local.truenas_dataset_mount_points[each.value.dataset_key], null)
  provider      = truenas.hosts[each.value.target]
  readonly      = try(each.value.readonly, false)
  security      = ["SYS"]

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
  provider              = truenas.hosts[each.value.host]
  threads               = each.value.compute.threads
  time                  = "UTC"
  vcpus                 = each.value.compute.sockets

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = try(local.machines[each.value.host].platform == "truenas", false)
      error_message = "The configured TrueNAS compute host must reference a TrueNAS server."
    }
  }
}

resource "truenas_vm_device" "cdrom" {
  for_each = local.truenas_virtual_machine_cdrom_devices

  attributes = each.value.attributes
  dtype      = each.value.dtype
  order      = each.value.order
  provider   = truenas.hosts[local.truenas_virtual_machines[each.value.virtual_machine].host]
  vm         = tonumber(truenas_vm.virtual_machine[each.value.virtual_machine].id)

  lifecycle {
    # Installation media is bootstrap-only; live Talos upgrades use machine configuration.
    ignore_changes = [attributes]
  }
}

resource "truenas_vm_device" "virtual_machine" {
  for_each = local.truenas_virtual_machine_devices

  attributes = each.value.attributes
  dtype      = each.value.dtype
  order      = each.value.order
  provider   = truenas.hosts[local.truenas_virtual_machines[each.value.virtual_machine].host]
  vm         = tonumber(truenas_vm.virtual_machine[each.value.virtual_machine].id)
}

resource "truenas_zvol" "virtual_machine_boot" {
  for_each = local.truenas_virtual_machines

  comments     = "${title(local.machines[each.key].platform)} boot disk for ${local.machine_fqdns[each.key]}"
  compression  = "LZ4"
  name         = "virtual-machines/${each.key}"
  pool         = each.value.boot.pool
  provider     = truenas.hosts[each.value.host]
  volblocksize = "16K"
  volsize      = each.value.boot.size_mib * 1024 * 1024

  lifecycle {
    prevent_destroy = true
  }
}
