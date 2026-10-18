locals {
  access              = yamldecode(file("${path.module}/data/access.yaml"))
  clusters            = yamldecode(file("${path.module}/data/clusters.yaml")).clusters
  domains             = yamldecode(file("${path.module}/data/domains.yaml")).domains
  machines_by_network = yamldecode(file("${path.module}/data/machines.yaml")).machines
  networks            = yamldecode(file("${path.module}/data/networks.yaml")).networks
  provider_settings   = yamldecode(file("${path.module}/data/providers.yaml"))
  storage             = yamldecode(file("${path.module}/data/storage.yaml"))

  infrastructure_inventory = {
    cloudflare = {
      account_id = data.cloudflare_account.default.id
      tunnels    = { for name, tunnel in cloudflare_zero_trust_tunnel_cloudflared.cluster : name => tunnel.id }
    }
    hosts = {
      for name, machine in local.machines : name => try(coalesce(
        try(local.dns_records_derived_specs["machine/${name}/a"].name, local.dns_records_derived_specs["machine/${name}/aaaa"].name, null),
        try(local.tailscale_device_addresses[local.tailscale_machine_device_names[name]].ipv4, null),
        try(format("%s.%s",
          local.machine_hostnames[name],
          data.unifi_network.configured[local.unifi_clients[lower(machine.interfaces[0].mac_address)].network_key].domain_name,
        ), null),
        local.machine_private_ipv4_addresses[name],
        try(machine.public_ipv4, null),
      ), null)
    }
    tailscale = merge(
      {
        for name, device_name in local.tailscale_machine_device_names :
        name => local.tailscale_devices[device_name].node_id
        if can(local.tailscale_devices[device_name])
      },
      {
        for name in keys(local.clusters) : name => local.tailscale_devices[name].node_id
        if can(local.tailscale_devices[name])
      },
    )
  }

  machine_cluster_names_duplicate = setintersection(
    toset(keys(local.machines)),
    toset(keys(local.clusters)),
  )

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
        mac     = lower(interface.mac_address)
        machine = machine_name
        network = machine.network
        primary = interface_index == 0
        subnet = try(one([
          for subnet_name, subnet in try(local.networks[machine.network].subnets, {}) : subnet_name
          if try(interface.address, null) != null && cidrcontains(subnet.cidr, interface.address)
        ]), null)
      }
    ]
  ])

  machine_names_duplicate = [
    for name in distinct(flatten([
      for machines in values(local.machines_by_network) : keys(machines)
    ])) : name
    if length([
      for machines in values(local.machines_by_network) : name
      if can(machines[name])
    ]) > 1
  ]

  machine_network_addresses = concat(
    [
      for interface in local.machine_interface_assignments : "${interface.network}/${interface.address}"
      if interface.address != null
    ],
    [
      for name, machine in local.machines : "${machine.network}/${local.machine_private_ipv4_addresses[name]}"
      if length(try(machine.interfaces, [])) == 0 && local.machine_private_ipv4_addresses[name] != null
    ],
  )

  machine_private_ipv4_addresses = {
    for name, machine in local.machines :
    name => try(machine.interfaces[0].address, machine.private_ipv4, null)
  }

  machine_public_ipv4_addresses = compact([
    for machine in values(local.machines) : try(machine.public_ipv4, null)
  ])

  machine_public_ipv6_addresses = compact([
    for machine in values(local.machines) : try(machine.public_ipv6, null)
  ])

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
