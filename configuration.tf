resource "terraform_data" "configuration_validation" {
  input = {
    clusters = sort(keys(local.clusters))
    machines = sort(keys(local.machines))
  }

  lifecycle {
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
      condition = length(distinct([
        for name, machine in local.machines : "${machine.network}/${local.machine_hostnames[name]}"
      ])) == length(local.machines)
      error_message = "Machine hostnames must be unique within each network."
    }

    precondition {
      condition = alltrue([
        for name in keys(local.networks) : can(regex(local.configuration_dns_label_pattern, name))
      ])
      error_message = "Network names must be valid lowercase DNS labels."
    }
  }
}
