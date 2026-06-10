locals {
  servers_validation_beszel_targets_missing = [
    for server_key, server in local.servers_input : server_key
    if(
      server.features.beszel_agent &&
      try(local.services_input["beszel-agent"].targets[server_key], null) == null
    )
  ]

  servers_validation_beszel_targets_unexpected = [
    for target_key in keys(local.services_input["beszel-agent"].targets) : target_key
    if try(!local.servers_input[target_key].features.beszel_agent, true)
  ]

  servers_validation_invalid_incus_vm_parents = [
    for server_key, server in local.servers_input : server_key
    if(
      server.platform == "incus" &&
      server.type == "vm" &&
      (
        server.parent == "" ||
        try(
          local.servers_input[server.parent].platform != "incus" ||
          local.servers_input[server.parent].type != "server" ||
          local.servers_input[server.parent].networking.management_host == "",
          true
        )
      )
    )
  ]

  servers_validation_invalid_oci_types = [
    for server_key, server in local.servers_input : server_key
    if(
      server.platform == "oci" &&
      server.type != "vm"
    )
  ]

  servers_validation_invalid_parents = [
    for server_key, server in local.servers_input : "${server_key} -> ${server.parent}"
    if(
      server.parent != "" &&
      try(local.servers_input[server.parent], null) == null
    )
  ]

  servers_validation_invalid_types = [
    for server_key, server in local.servers_input : server_key
    if try(local.defaults.server_types[server.type], null) == null
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
    if(
      server.parent != "" &&
      try(local.servers_input[local.servers_input[server.parent].parent].parent != "", false)
    )
  ]

  servers_validation_oci_always_free_a1_cpus = sum([
    for server in values(local.servers_input) : server.platform_config.oci.cpus
    if(
      server.platform == "oci" &&
      server.type == "vm" &&
      server.platform_config.oci.shape == "VM.Standard.A1.Flex"
    )
  ])

  servers_validation_oci_always_free_a1_memory = sum([
    for server in values(local.servers_input) : server.platform_config.oci.memory
    if(
      server.platform == "oci" &&
      server.type == "vm" &&
      server.platform_config.oci.shape == "VM.Standard.A1.Flex"
    )
  ])

  servers_validation_oci_always_free_boot_volume_gbs = sum([
    for server in values(local.servers_input) : server.platform_config.oci.disk_size
    if(
      server.platform == "oci" &&
      server.type == "vm"
    )
  ])

  servers_validation_oci_always_free_micro_instances = length([
    for server in values(local.servers_input) : server
    if(
      server.platform == "oci" &&
      server.type == "vm" &&
      server.platform_config.oci.shape == "VM.Standard.E2.1.Micro"
    )
  ])

  servers_validation_oci_always_free_shapes_invalid = [
    for server_key, server in local.servers_input : server_key
    if(
      server.platform == "oci" &&
      server.type == "vm" &&
      !contains(["VM.Standard.A1.Flex", "VM.Standard.E2.1.Micro"], server.platform_config.oci.shape)
    )
  ]

  servers_validation_parent_cycles = [
    for server_key, server in local.servers_input : server_key
    if(
      server.parent != "" &&
      (
        try(local.servers_input[server.parent].parent == server_key, false) ||
        try(local.servers_input[local.servers_input[server.parent].parent].parent == server_key, false)
      )
    )
  ]

  servers_validation_self_parents = [
    for server_key, server in local.servers_input : server_key
    if server.parent == server_key
  ]
}

resource "terraform_data" "servers_validation" {
  input = keys(local.servers_input)

  lifecycle {
    precondition {
      condition     = length(local.servers_validation_beszel_targets_missing) == 0
      error_message = "Servers with features.beszel_agent enabled require a matching beszel-agent service target: ${join(", ", nonsensitive(local.servers_validation_beszel_targets_missing))}"
    }

    precondition {
      condition     = length(local.servers_validation_beszel_targets_unexpected) == 0
      error_message = "Beszel agent service targets require features.beszel_agent on the target server: ${join(", ", nonsensitive(local.servers_validation_beszel_targets_unexpected))}"
    }

    # Incus remotes are configured from parent server management addresses.
    precondition {
      condition     = length(local.servers_validation_invalid_incus_vm_parents) == 0
      error_message = "Incus VMs must reference an Incus server parent with networking.management_host set: ${join(", ", nonsensitive(local.servers_validation_invalid_incus_vm_parents))}"
    }

    # OCI resources in this stack only model VM instances, not bare metal or
    # appliance/server abstractions.
    precondition {
      condition     = length(local.servers_validation_invalid_oci_types) == 0
      error_message = "OCI servers must be type vm: ${join(", ", nonsensitive(local.servers_validation_invalid_oci_types))}"
    }

    precondition {
      condition     = length(local.servers_validation_invalid_parents) == 0
      error_message = "Invalid parent references found in servers configuration: ${join(", ", nonsensitive(local.servers_validation_invalid_parents))}"
    }

    precondition {
      condition     = length(local.servers_validation_invalid_types) == 0
      error_message = "Invalid server types found: ${join(", ", nonsensitive(local.servers_validation_invalid_types))}"
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
      error_message = "Server parent inheritance supports at most two parent levels: ${join(", ", nonsensitive(local.servers_validation_long_parent_chains))}"
    }

    # OCI Always Free quota enforcement. Only checked when var.oci_always_free is true.
    precondition {
      condition = (
        !var.oci_always_free ||
        length(local.servers_validation_oci_always_free_shapes_invalid) == 0
      )
      error_message = "OCI VM shape must be Always Free eligible (VM.Standard.A1.Flex or VM.Standard.E2.1.Micro): ${join(", ", nonsensitive(local.servers_validation_oci_always_free_shapes_invalid))}"
    }

    precondition {
      condition = (
        !var.oci_always_free ||
        local.servers_validation_oci_always_free_a1_cpus <= 4
      )
      error_message = "Always Free A1 Flex total OCPUs must not exceed 4 (got ${nonsensitive(local.servers_validation_oci_always_free_a1_cpus)})."
    }

    precondition {
      condition = (
        !var.oci_always_free ||
        local.servers_validation_oci_always_free_a1_memory <= 24
      )
      error_message = "Always Free A1 Flex total memory must not exceed 24 GB (got ${nonsensitive(local.servers_validation_oci_always_free_a1_memory)} GB)."
    }

    precondition {
      condition = (
        !var.oci_always_free ||
        local.servers_validation_oci_always_free_micro_instances <= 2
      )
      error_message = "Always Free Micro instances must not exceed 2 (got ${nonsensitive(local.servers_validation_oci_always_free_micro_instances)})."
    }

    precondition {
      condition = (
        !var.oci_always_free ||
        local.servers_validation_oci_always_free_boot_volume_gbs <= 200
      )
      error_message = "Always Free total boot volume size must not exceed 200 GB (got ${nonsensitive(local.servers_validation_oci_always_free_boot_volume_gbs)} GB)."
    }

    # Catch short cycles before inherited address lookup hides the root cause.
    precondition {
      condition = length(local.servers_validation_parent_cycles) == 0
      error_message = (
        "Server parent references contain a cycle within the supported parent depth: ${join(", ", local.servers_validation_parent_cycles)}"
      )
    }

    precondition {
      condition     = length(local.servers_validation_self_parents) == 0
      error_message = "Servers cannot set themselves as their own parent: ${join(", ", nonsensitive(local.servers_validation_self_parents))}"
    }
  }
}
