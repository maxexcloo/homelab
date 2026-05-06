locals {
  servers_validation_invalid_incus_vm_parents = [
    for server_key, server in local.servers_input : server_key
    if server.platform == "incus" && server.type == "vm" && (
      server.parent == "" ||
      try(
        local.servers_input[server.parent].platform != "incus" ||
        local.servers_input[server.parent].type != "server" ||
        local.servers_input[server.parent].networking.management_address == "",
        true
      )
    )
  ]

  servers_validation_invalid_oci_types = [
    for server_key, server in local.servers_input : server_key
    if server.platform == "oci" && server.type != "vm"
  ]

  servers_validation_invalid_parents = [
    for server_key, server in local.servers_input : "${server_key} -> ${server.parent}"
    if server.parent != "" && !contains(keys(local.servers_input), server.parent)
  ]

  servers_validation_invalid_types = [
    for server_key, server in local.servers_input : server_key
    if !contains(keys(local.defaults.types), server.type)
  ]

  servers_validation_key_mismatches = [
    for server_key, server in local.servers_input : "${server_key} -> ${server.identity.name}"
    if server_key != (
      server.identity.name == server.identity.region ? server.identity.region :
      server.parent != "" ? "${server.parent}-${server.identity.name}" :
      "${server.identity.region}-${server.identity.name}"
    )
  ]

  servers_validation_long_parent_chains = [
    for server_key, server in local.servers_input : server_key
    if server.parent != "" && try(local.servers_input[local.servers_input[server.parent].parent].parent != "", false)
  ]

  servers_validation_parent_cycles = [
    for server_key, server in local.servers_input : server_key
    if server.parent != "" && (
      try(local.servers_input[server.parent].parent == server_key, false) ||
      try(local.servers_input[local.servers_input[server.parent].parent].parent == server_key, false)
    )
  ]

  servers_validation_pushover_missing_credentials = [
    for server_key, server in local.servers_input : server_key
    if server.features.pushover && (nonsensitive(var.pushover_application_token) == "" || nonsensitive(var.pushover_user_key) == "")
  ]

  servers_validation_self_parents = [
    for server_key, server in local.servers_input : server_key
    if server.parent == server_key
  ]
}

resource "terraform_data" "servers_validation" {
  input = keys(local.servers_input)

  lifecycle {
    # Incus remotes are configured from parent server management addresses.
    precondition {
      condition     = length(local.servers_validation_invalid_incus_vm_parents) == 0
      error_message = "Incus VMs must reference an Incus server parent with networking.management_address set: ${join(", ", local.servers_validation_invalid_incus_vm_parents)}"
    }

    # OCI resources in this stack only model VM instances, not bare metal or
    # appliance/server abstractions.
    precondition {
      condition     = length(local.servers_validation_invalid_oci_types) == 0
      error_message = "OCI servers must be type vm: ${join(", ", local.servers_validation_invalid_oci_types)}"
    }

    precondition {
      condition     = length(local.servers_validation_invalid_parents) == 0
      error_message = "Invalid parent references found in servers configuration: ${join(", ", local.servers_validation_invalid_parents)}"
    }

    precondition {
      condition     = length(local.servers_validation_invalid_types) == 0
      error_message = "Invalid server types found: ${join(", ", local.servers_validation_invalid_types)}"
    }

    precondition {
      condition = length(local.servers_validation_key_mismatches) == 0
      error_message = (
        "Server YAML filenames must match the derived key (region for region roots, parent-name when parent is set, otherwise region-name): ${join(", ", local.servers_validation_key_mismatches)}"
      )
    }

    # OpenTofu locals are not generally recursive; keep the supported inheritance
    # depth explicit so addressing behavior remains predictable.
    precondition {
      condition     = length(local.servers_validation_long_parent_chains) == 0
      error_message = "Server parent inheritance supports at most two parent levels: ${join(", ", local.servers_validation_long_parent_chains)}"
    }

    # Catch short cycles before inherited address lookup hides the root cause.
    precondition {
      condition = length(local.servers_validation_parent_cycles) == 0
      error_message = (
        "Server parent references contain a cycle within the supported parent depth: ${join(", ", local.servers_validation_parent_cycles)}"
      )
    }

    # Pushover values are pass-through variables, so provider validation will not
    # catch missing credentials for enabled servers.
    precondition {
      condition = length(local.servers_validation_pushover_missing_credentials) == 0
      error_message = (
        "Servers with features.pushover enabled require pushover_application_token and pushover_user_key: ${join(", ", local.servers_validation_pushover_missing_credentials)}"
      )
    }

    precondition {
      condition     = length(local.servers_validation_self_parents) == 0
      error_message = "Servers cannot set themselves as their own parent: ${join(", ", local.servers_validation_self_parents)}"
    }
  }
}
