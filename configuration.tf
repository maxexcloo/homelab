resource "terraform_data" "configuration_validation" {
  lifecycle {
    precondition {
      condition = (
        length(distinct(local.machine_interface_assignments[*].client_mac)) == length(local.machine_interface_assignments) &&
        length(distinct(local.machine_interface_assignments[*].mac)) == length(local.machine_interface_assignments) &&
        length(distinct(local.machine_network_addresses)) == length(local.machine_network_addresses) &&
        length(distinct(local.machine_public_ipv4_addresses)) == length(local.machine_public_ipv4_addresses) &&
        length(distinct(local.machine_public_ipv6_addresses)) == length(local.machine_public_ipv6_addresses)
      )
      error_message = "Machine MAC addresses and network-scoped private and public IP addresses must be unique."
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
      condition = length(distinct([
        for name, machine in local.machines : "${machine.network}/${local.machine_hostnames[name]}"
      ])) == length(local.machines)
      error_message = "Machine hostnames must be unique within each network."
    }
  }
}
