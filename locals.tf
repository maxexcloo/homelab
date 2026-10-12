locals {
  access                          = yamldecode(file("${path.module}/data/access.yaml"))
  clusters                        = yamldecode(file("${path.module}/data/clusters.yaml")).clusters
  configuration_dns_label_pattern = "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"
  domains                         = yamldecode(file("${path.module}/data/domains.yaml")).domains
  machines_by_network             = yamldecode(file("${path.module}/data/machines.yaml")).machines
  networks                        = yamldecode(file("${path.module}/data/networks.yaml")).networks
  provider_settings               = yamldecode(file("${path.module}/data/providers.yaml"))
  storage                         = yamldecode(file("${path.module}/data/storage.yaml"))

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
    tailscale = {
      for name, device_name in local.tailscale_machine_device_names :
      name => local.tailscale_devices[device_name].node_id
      if can(local.tailscale_devices[device_name])
    }
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
}

resource "terraform_data" "configuration_validation" {
  input = {
    clusters = sort(keys(local.clusters))
    machines = sort(keys(local.machines))
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for machine in values(local.machines) : try(machine.smtp, null) == null || try(machine.smtp == "resend", false)
      ])
      error_message = "Machine SMTP providers must be Resend."
    }

    precondition {
      condition = alltrue([
        for cluster in values(local.clusters) : can(cluster.nodes[cluster.api_node])
      ])
      error_message = "Every cluster API node must belong to that cluster."
    }

    precondition {
      condition = alltrue([
        for cluster in values(local.clusters) : try(cluster.nodes[cluster.api_node].machine_type == "controlplane", false)
      ])
      error_message = "Every cluster API node must be a control plane."
    }

    precondition {
      condition = alltrue(flatten([
        for cluster in values(local.clusters) : [
          for node_name in keys(cluster.nodes) : can(local.machines[node_name])
        ]
      ]))
      error_message = "Every cluster node must reference an existing machine."
    }

    precondition {
      condition = alltrue(flatten([
        for cluster in values(local.clusters) : [
          for node_name, node in cluster.nodes : (
            contains(["api", "metadata"], try(node.configuration_delivery, "")) &&
            (try(node.configuration_delivery, "") != "metadata" || try(local.machines[node_name].provider, null) == "oci")
          )
        ]
      ]))
      error_message = "Every cluster node must use API or OCI metadata configuration delivery."
    }

    precondition {
      condition = alltrue(flatten([
        for cluster in values(local.clusters) : [
          for node_name in keys(cluster.nodes) : try(local.machines[node_name].platform == "talos", false)
        ]
      ]))
      error_message = "Every cluster node machine must use the Talos platform."
    }

    precondition {
      condition = alltrue([
        for cluster in values(local.clusters) : length([
          for node in values(cluster.nodes) : node
          if node.machine_type == "controlplane" && try(node.bootstrap, false)
        ]) == 1
      ])
      error_message = "Every enabled Talos cluster must have exactly one bootstrap control plane."
    }

    precondition {
      condition = alltrue([
        for machine in values(local.machines) : can(local.networks[machine.network])
      ])
      error_message = "Every machine must reference an existing network."
    }

    precondition {
      condition = alltrue([
        for name, machine in local.machines : (
          (local.machine_private_ipv4_addresses[name] == null || can(cidrnetmask("${local.machine_private_ipv4_addresses[name]}/32"))) &&
          (try(machine.public_ipv4, null) == null || can(cidrnetmask("${machine.public_ipv4}/32"))) &&
          (try(machine.public_ipv6, null) == null || try(strcontains(machine.public_ipv6, ":") && can(cidrhost("${machine.public_ipv6}/128", 0)), false))
        )
      ])
      error_message = "Machine addresses must use valid IPv4 or IPv6 syntax."
    }

    precondition {
      condition = (
        length(distinct(local.machine_interface_assignments[*].mac)) == length(local.machine_interface_assignments) &&
        length(distinct(local.machine_network_addresses)) == length(local.machine_network_addresses) &&
        length(distinct(local.machine_public_ipv4_addresses)) == length(local.machine_public_ipv4_addresses) &&
        length(distinct(local.machine_public_ipv6_addresses)) == length(local.machine_public_ipv6_addresses)
      )
      error_message = "Machine MAC addresses and network-scoped private and public IP addresses must be unique."
    }

    precondition {
      condition = alltrue([
        for mac_address in local.machine_interface_assignments[*].mac : can(regex("^([0-9a-f]{2}:){5}[0-9a-f]{2}$", mac_address))
      ])
      error_message = "Machine MAC addresses must use six colon-separated octets."
    }

    precondition {
      condition = alltrue([
        for machine in values(local.machines) : !can(machine.interfaces) || (
          length(machine.interfaces) > 0 &&
          try(machine.interfaces[0].address != null, false) &&
          !can(machine.private_ipv4)
        )
        ]) && alltrue([
        for assignment in local.machine_interface_assignments : (
          assignment.address == null || can(cidrnetmask("${assignment.address}/32"))
        )
      ])
      error_message = "Machine interfaces must use a non-null primary IPv4 address, valid optional secondary IPv4 addresses, and no separate private IPv4 address."
    }

    precondition {
      condition = alltrue([
        for assignment in local.machine_interface_assignments : assignment.address == null || assignment.subnet != null
      ])
      error_message = "Every configured machine interface address must belong to exactly one configured network subnet."
    }

    precondition {
      condition = alltrue([
        for name, machine in local.machines : try(machine.provider, null) != "oci" || try(
          cidrcontains(local.networks[machine.network].oci.subnet_cidr, local.machine_private_ipv4_addresses[name]),
          false,
        )
      ])
      error_message = "Every OCI machine address must belong to its configured OCI subnet."
    }

    precondition {
      condition = alltrue([
        for name in keys(local.clusters) : can(regex(local.configuration_dns_label_pattern, name))
      ])
      error_message = "Cluster names must be valid lowercase DNS labels."
    }

    precondition {
      condition = alltrue([
        for hostname in values(local.machine_hostnames) : can(regex(local.configuration_dns_label_pattern, hostname))
      ])
      error_message = "Machine hostnames must be valid lowercase DNS labels."
    }

    precondition {
      condition = alltrue([
        for name in keys(local.machines) : can(regex(local.configuration_dns_label_pattern, name))
      ])
      error_message = "Machine names must be valid lowercase DNS labels."
    }

    precondition {
      condition     = length(local.machine_cluster_names_duplicate) == 0
      error_message = "Machine and cluster names must not overlap: ${join(", ", sort(tolist(local.machine_cluster_names_duplicate)))}"
    }

    precondition {
      condition     = length(local.machine_names_duplicate) == 0
      error_message = "Machine names must be unique across networks: ${join(", ", sort(local.machine_names_duplicate))}"
    }

    precondition {
      condition = alltrue(flatten([
        for machine in values(local.machines) : [
          for service in values(try(machine.services, {})) : try(
            contains(["http", "https"], service.scheme) && service.port >= 1 && service.port <= 65535 && floor(service.port) == service.port,
            false,
          )
        ]
      ]))
      error_message = "Machine services must use HTTP or HTTPS and integer ports from 1 to 65535."
    }

    precondition {
      condition = alltrue([
        for machine in values(local.machines) : try(machine.type, null) == null || can(regex(local.configuration_dns_label_pattern, machine.type))
      ])
      error_message = "Machine types must be valid lowercase labels."
    }

    precondition {
      condition = alltrue([
        for name in values(local.machine_tailscale_names) : can(regex(local.configuration_dns_label_pattern, name))
      ])
      error_message = "Derived Tailscale device names must be valid lowercase DNS labels."
    }

    precondition {
      condition = length(distinct([
        for name, machine in local.machines : "${machine.network}/${local.machine_hostnames[name]}"
      ])) == length(local.machines)
      error_message = "Machine hostnames must be unique within each network."
    }

    precondition {
      condition = length(flatten([
        for cluster in values(local.clusters) : keys(cluster.nodes)
      ])) == length(local.machine_clusters)
      error_message = "A machine may belong to only one cluster."
    }

    precondition {
      condition = alltrue([
        for name in keys(local.networks) : can(regex(local.configuration_dns_label_pattern, name))
      ])
      error_message = "Network names must be valid lowercase DNS labels."
    }
  }
}
