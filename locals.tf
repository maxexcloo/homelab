locals {
  access = yamldecode(file("${path.module}/data/access.yaml"))

  cloudflare = yamldecode(file("${path.module}/data/domains.yaml")).cloudflare

  clusters = yamldecode(file("${path.module}/data/clusters.yaml")).clusters

  configuration_dns_label_pattern = "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"

  domains = yamldecode(file("${path.module}/data/domains.yaml")).domains

  machines = yamldecode(file("${path.module}/data/machines.yaml")).machines

  networks = yamldecode(file("${path.module}/data/networks.yaml")).networks

  storage = yamldecode(file("${path.module}/data/storage.yaml"))

  machine_cluster_names_duplicate = setintersection(
    toset(keys(local.machines)),
    toset(keys(local.clusters)),
  )

  machine_fqdns = {
    for name, machine in local.machines :
    name => "${local.machine_hostnames[name]}.${machine.network}.${local.domains.infrastructure}"
  }

  machine_hostnames = {
    for name, machine in local.machines :
    name => try(machine.hostname, name)
  }
}

resource "terraform_data" "configuration_validation" {
  input = {
    clusters = sort(keys(local.clusters))
    machines = sort(keys(local.machines))
  }

  lifecycle {
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
        for cluster_name, cluster in local.clusters : [
          for node_name in keys(cluster.nodes) : try(local.machines[node_name].cluster == cluster_name, false)
        ]
      ]))
      error_message = "Every cluster node must reference a machine assigned to the same cluster."
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
        for cluster in values(local.clusters) : !cluster.talos_enabled || length([
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
      condition = alltrue([
        for machine in values(local.machines) : try(machine.management_port, null) == null || try(machine.management_port >= 1 && machine.management_port <= 65535, false)
      ])
      error_message = "Machine management ports must be integers from 1 to 65535."
    }

    precondition {
      condition = alltrue([
        for machine in values(local.machines) : can(regex(local.configuration_dns_label_pattern, machine.tag))
      ])
      error_message = "Machine tags must be valid lowercase labels."
    }

    precondition {
      condition = alltrue([
        for machine in values(local.machines) : machine.platform == "talos" || try(trimspace(machine.username) != "", false)
      ])
      error_message = "Every non-Talos machine must declare a username."
    }

    precondition {
      condition = length(distinct([
        for name, machine in local.machines : "${machine.network}/${local.machine_hostnames[name]}"
      ])) == length(local.machines)
      error_message = "Machine hostnames must be unique within each network."
    }

    precondition {
      condition = alltrue([
        for machine_name, machine in local.machines : can(machine.cluster) ? can(local.clusters[machine.cluster].nodes[machine_name]) : true
      ])
      error_message = "Every clustered machine must belong to its referenced cluster."
    }

    precondition {
      condition = alltrue([
        for machine in values(local.machines) : can(machine.vlan) ? can(local.networks[machine.network].unifi.networks[machine.vlan]) : true
      ])
      error_message = "Every machine VLAN must reference an existing UniFi network."
    }

    precondition {
      condition = alltrue([
        for name in keys(local.networks) : can(regex(local.configuration_dns_label_pattern, name))
      ])
      error_message = "Network names must be valid lowercase DNS labels."
    }

    precondition {
      condition = alltrue([
        for machine in values(local.machines) : can(local.access.tailscale.tag_owners["tag:${machine.tag}"])
      ])
      error_message = "Every machine tag must have a Tailscale owner."
    }
  }
}
