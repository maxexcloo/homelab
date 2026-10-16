data "truenas_network_interface" "services_physical" {
  for_each = local.truenas_hosts_services

  id       = each.value.interface.name
  provider = truenas.hosts[each.key]
}

locals {
  truenas_datasets = merge([
    for target, storage in local.truenas_storage : {
      for name, dataset in storage.datasets : "${target}/${name}" => merge(dataset, {
        name               = try(dataset.name, name)
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

  truenas_host_services_prefix_lengths = {
    for name, host in local.truenas_hosts_services : name => tonumber(split(
      "/",
      local.networks[host.machine.network].subnets[
        local.truenas_machine_interfaces_by_mac[lower(host.interface.mac_address)].subnet
      ].cidr,
    )[1])
  }

  truenas_hosts = {
    for name, machine in local.machines : name => machine
    if machine.platform == "truenas"
  }

  truenas_hosts_services = {
    for name, machine in local.truenas_hosts : name => {
      interface = one([
        for interface in machine.interfaces : interface
        if try(interface.bridge, null) != null
      ])
      machine = machine
    }
    if length([
      for interface in machine.interfaces : interface
      if try(interface.bridge, null) != null
    ]) == 1
  }

  truenas_machine_interfaces_by_mac = {
    for interface in local.machine_interface_assignments : interface.mac => interface
  }

  truenas_storage = {
    for target, storage in local.storage.truenas : target => merge(storage, {
      datasets = {
        for name, dataset in storage.datasets : name => merge(storage.dataset_defaults, dataset)
      }
    })
  }
}

resource "terraform_data" "truenas_storage_target" {
  for_each = local.truenas_storage

  input = each.key

  lifecycle {
    precondition {
      condition     = can(local.truenas_hosts[each.key])
      error_message = "Every TrueNAS storage configuration must reference an existing TrueNAS host."
    }

    precondition {
      condition     = try(trimspace(local.truenas_hosts_services[each.key].interface.name) != "", false)
      error_message = "Every managed TrueNAS host must declare exactly one named bridged interface."
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

resource "truenas_mail_config" "host" {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if contains(local.resend_hosts, name)
  }

  fromemail      = "${each.value.network}-${local.machine_hostnames[each.key]}@${local.domains.infrastructure}"
  fromname       = "${each.value.network}-${local.machine_hostnames[each.key]}"
  outgoingserver = "smtp.resend.com"
  pass           = resend_api_key.host[each.key].token
  port           = 587
  provider       = truenas.hosts[each.key]
  security       = "TLS"
  smtp           = true
  user           = "resend"
}

resource "truenas_network_interface" "services_bridge" {
  for_each = local.truenas_hosts_services

  bridge_members = [truenas_network_interface.services_physical[each.key].name]
  ipv4_dhcp      = false
  ipv6_auto      = false
  name           = each.value.interface.bridge
  provider       = truenas.hosts[each.key]
  rollback       = true
  type           = "BRIDGE"

  aliases = [
    {
      address = each.value.interface.address
      netmask = local.truenas_host_services_prefix_lengths[each.key]
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
  name      = each.value.interface.name
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
            one(data.truenas_network_interface.services_physical[each.key].aliases).address == each.value.interface.address &&
            one(data.truenas_network_interface.services_physical[each.key].aliases).netmask == local.truenas_host_services_prefix_lengths[each.key],
            false,
          )
        )
      )
      error_message = "The live Services NIC on ${each.key} must be a static physical interface holding the expected IPv4 address before bridge adoption, or no address after adoption."
    }
  }
}
