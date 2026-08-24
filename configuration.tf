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
      condition = alltrue(flatten([
        for cluster_name, cluster in local.clusters : [
          for node_name in keys(cluster.nodes) : try(local.machines[node_name].cluster == cluster_name, false)
        ]
      ]))
      error_message = "Every cluster node must reference a machine assigned to the same cluster."
    }

    precondition {
      condition = alltrue([
        for machine in values(local.machines) : can(local.networks[machine.network])
      ])
      error_message = "Every machine must reference an existing network."
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
        for machine in values(local.machines) : can(local.access.tailscale.tag_owners["tag:${machine.tailscale_tag}"])
      ])
      error_message = "Every machine Tailscale tag must have an owner."
    }
  }
}
