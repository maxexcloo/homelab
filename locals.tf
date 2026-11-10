locals {
  access              = yamldecode(file("${path.module}/data/access.yaml"))
  domains             = yamldecode(file("${path.module}/data/domains.yaml")).domains
  machines_by_network = yamldecode(file("${path.module}/data/machines.yaml")).machines
  networks            = yamldecode(file("${path.module}/data/networks.yaml")).networks
  provider_settings   = yamldecode(file("${path.module}/data/providers.yaml"))
  storage             = yamldecode(file("${path.module}/data/storage.yaml")).truenas
  versions            = yamldecode(file("${path.module}/data/versions.yaml"))

  clusters = {
    for name, cluster in yamldecode(file("${path.module}/data/clusters.yaml")).clusters : name => merge(cluster, {
      kubernetes_version = local.versions.kubernetes
      talos_version      = local.versions.talos
    })
  }

  machine_clusters = merge([
    for cluster_name, cluster in local.clusters : {
      for node_name in keys(cluster.nodes) : node_name => cluster_name
    }
  ]...)

  machine_fqdns = {
    for name, machine in local.machines :
    name => "${local.machine_hostnames[name]}.${machine.network}.${local.domains.infrastructure}"
  }

  machine_hostnames = {
    for name, machine in local.machines :
    name => try(machine.hostname, name)
  }

  machine_interface_assignments = flatten([
    for machine_name, machine in local.machines : [
      for interface_index, interface in try(machine.interfaces, []) : {
        address = try(interface.address, null)
        bridge  = try(interface.bridge, null)
        # A bridge answers for its address with its own MAC, not its member's.
        client_mac = lower(try(interface.bridge, null) == null ? interface.mac_address : interface.bridge_mac_address)
        mac        = lower(interface.mac_address)
        machine    = machine_name
        name       = try(interface.name, null)
        network    = machine.network
        primary    = interface_index == 0
        subnet = try(one([
          for subnet_name, subnet in try(local.networks[machine.network].subnets, {}) : subnet_name
          if try(interface.address, null) != null && cidrcontains(subnet.cidr, interface.address)
        ]), null)
      }
    ]
  ])

  machine_login_titles = {
    for name, machine in local.machines :
    name => "${title(machine.type)}: ${local.machine_fqdns[name]}"
    if can(machine.type)
  }

  machine_private_ipv4_addresses = {
    for name, machine in local.machines :
    name => try(machine.interfaces[0].address, machine.private_ipv4, null)
  }

  machine_tailscale_names = {
    for name, machine in local.machines :
    name => "${machine.network}-${local.machine_hostnames[name]}"
    if try(machine.tailscale.enabled, true)
  }

  machines = merge([
    for network, machines in local.machines_by_network : {
      for name, machine in machines : name => merge(machine, { network = network }, can(local.machine_clusters[name]) ? { cluster = local.machine_clusters[name] } : {})
    }
  ]...)

  managed_comment = "Homelab OpenTofu Managed"
}
