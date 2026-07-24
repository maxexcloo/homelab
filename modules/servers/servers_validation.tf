locals {
  _servers_validation_cloudflare_routes_missing = flatten([
    for server_key, server in local.servers_model : [
      for route in server.routing.routes : "${server_key} -> ${route.host}"
      if(
        route.expose == "cloudflare" &&
        !server.features.cloudflared
      )
    ]
  ])

  _servers_validation_credential_names = {
    for server_key, server in local.servers_input : server_key => concat(
      keys(server.credentials.fields),
      flatten([
        for credential_name, generator in server.credentials.generated :
        generator.type == "x509" ? ["${credential_name}_certificate", "${credential_name}_private_key"] : [credential_name]
      ]),
      ["age_secret_key"],
      server.features.beszel ? ["beszel_agent_token", "beszel_system_id"] : [],
      server.features.bootstrap && server.platform == "truenas" ? ["truenas_cd_access_token"] : [],
      server.features.cloudflare_acme ? ["cloudflare_acme_token"] : [],
      server.features.cloudflare_acme_legacy ? ["cloudflare_acme_legacy_token"] : [],
      server.features.cloudflared ? ["cloudflare_tunnel_read_token", "cloudflare_tunnel_token"] : [],
      server.features.docker ? ["doco_cd_git_access_token", "doco_cd_webhook_secret"] : [],
      server.features.mail ? ["mail_password"] : [],
      server.features.object_storage ? ["object_storage_secret_access_key"] : [],
      server.features.password ? ["password", "password_hash"] : [],
      server.features.tailscale ? ["tailscale_auth_key"] : [],
    )
  }

  _servers_validation_credential_names_conflicting = [
    for server_key, credential_names in local._servers_validation_credential_names : server_key
    if length(credential_names) != length(distinct(credential_names))
  ]

  _servers_validation_invalid_incus_vm_parents = [
    for server_key, server in local.incus_vm_requests : server_key
    if(
      server.parent == "" ||
      !can(local.incus_servers[server.parent])
    )
  ]

  _servers_validation_invalid_oci_types = [
    for server_key, server in local.oci_servers : server_key
    if server.type != "vm"
  ]

  _servers_validation_invalid_parents = [
    for server_key, server in local.servers_input : "${server_key} -> ${server.parent}"
    if(
      server.parent != "" &&
      !can(local.servers_input[server.parent])
    )
  ]

  _servers_validation_invalid_types = [
    for server_key, server in local.servers_input : server_key
    if !can(local.defaults.server_types[server.type])
  ]

  _servers_validation_key_mismatches = [
    for server_key, server in local.servers_input : "${server_key} -> ${server.identity.name}"
    if server_key != (
      server.identity.name == server.identity.region ? server.identity.region :
      server.parent != "" ? "${server.parent}-${server.identity.name}" :
      "${server.identity.region}-${server.identity.name}"
    )
  ]

  _servers_validation_long_parent_chains = [
    for server_key, server in local.servers_input : server_key
    if(
      server.parent != "" &&
      try(local.servers_input[local.servers_input[server.parent].parent].parent != "", false)
    )
  ]

  _servers_validation_managed_zone_matches = {
    for host in distinct(flatten([
      for server in values(local.servers_input) : [
        for route in server.routing.routes : route.host
      ]
      ])) : host => [
      for zone in keys(var.dns) : zone
      if(
        host == zone ||
        endswith(host, ".${zone}")
      )
    ]
  }

  _servers_validation_oci_always_free_a1_cpus = sum([
    for vm in values(local.oci_vms) : vm.platform_config.oci.cpus
    if(
      vm.platform_config.oci.shape == "VM.Standard.A1.Flex"
    )
  ])

  _servers_validation_oci_always_free_a1_memory = sum([
    for vm in values(local.oci_vms) : vm.platform_config.oci.memory
    if(
      vm.platform_config.oci.shape == "VM.Standard.A1.Flex"
    )
  ])

  _servers_validation_oci_always_free_boot_volume_gbs = sum([
    for vm in values(local.oci_vms) : vm.platform_config.oci.disk_size
  ])

  _servers_validation_oci_always_free_micro_instances = length([
    for vm in values(local.oci_vms) : vm
    if vm.platform_config.oci.shape == "VM.Standard.E2.1.Micro"
  ])

  _servers_validation_oci_always_free_shapes_invalid = [
    for vm_key, vm in local.oci_vms : vm_key
    if !contains(["VM.Standard.A1.Flex", "VM.Standard.E2.1.Micro"], vm.platform_config.oci.shape)
  ]

  _servers_validation_oci_ingress_rule_names_not_unique = [
    for vm_key, vm in local.oci_vms : vm_key
    if length(vm.platform_config.oci.ingress_rules) != length(distinct([
      for rule in vm.platform_config.oci.ingress_rules : rule.name
    ]))
  ]

  _servers_validation_oci_ingress_rules_invalid = flatten([
    for vm_key, vm in local.oci_vms : [
      for rule in vm.platform_config.oci.ingress_rules : "${vm_key} -> ${rule.protocol} ${rule.source}"
      if(
        !can(cidrhost(rule.source, 0)) ||
        (
          rule.protocol == "icmp" &&
          strcontains(rule.source, ":")
        ) ||
        (
          rule.protocol == "icmpv6" &&
          !strcontains(rule.source, ":")
        ) ||
        (
          rule.port_min != null &&
          rule.port_max < rule.port_min
        )
      )
    ]
  ])

  _servers_validation_parent_cycles = [
    for server_key, server in local.servers_input : server_key
    if(
      server.parent != "" &&
      (
        try(local.servers_input[server.parent].parent == server_key, false) ||
        try(local.servers_input[local.servers_input[server.parent].parent].parent == server_key, false)
      )
    )
  ]

  _servers_validation_routes_ids_not_unique = [
    for server_key, server in local.servers_model : server_key
    if length(server.routing.routes) != length(distinct([for route in server.routing.routes : route.id]))
  ]

  _servers_validation_routes_invalid_proxies = flatten([
    for server_key, server in local.servers_input : [
      for route in server.routing.routes : "${server_key}.${route.host} -> ${trimprefix(route.expose, "proxy-")}"
      if(
        startswith(route.expose, "proxy-") &&
        !can(local.servers_input[trimprefix(route.expose, "proxy-")])
      )
    ]
  ])

  _servers_validation_routes_missing_backend = flatten([
    for server_key, server in local.servers_input : [
      for route in server.routing.routes : "${server_key} -> ${route.host}"
      if try(route.backend_url, server.routing.backend_url) == ""
    ]
  ])

  _servers_validation_routes_not_unique = [
    for server_key, server in local.servers_input : server_key
    if length(server.routing.routes) != length(distinct([for route in server.routing.routes : route.host]))
  ]

  _servers_validation_routes_unmanaged = flatten([
    for server_key, server in local.servers_input : [
      for route in server.routing.routes : "${server_key} -> ${route.host}"
      if length(local._servers_validation_managed_zone_matches[route.host]) == 0
    ]
  ])

  _servers_validation_self_parents = [
    for server_key, server in local.servers_input : server_key
    if server.parent == server_key
  ]
}

resource "terraform_data" "servers_validation" {
  input = keys(local.servers_input)

  lifecycle {
    precondition {
      condition     = length(local._servers_validation_credential_names_conflicting) == 0
      error_message = "Server credential names must not overlap manual fields, generated outputs, or feature-created fields: ${join(", ", local._servers_validation_credential_names_conflicting)}"
    }

    precondition {
      condition     = length(local._servers_validation_cloudflare_routes_missing) == 0
      error_message = "Cloudflare server routes require features.cloudflared: ${join(", ", nonsensitive(local._servers_validation_cloudflare_routes_missing))}"
    }

    # Incus remotes are configured from parent server management addresses.
    precondition {
      condition     = length(local._servers_validation_invalid_incus_vm_parents) == 0
      error_message = "Incus VMs must reference an Incus server parent with networking.management_host set: ${join(", ", nonsensitive(local._servers_validation_invalid_incus_vm_parents))}"
    }

    # OCI resources in this stack only model VM instances, not bare metal or
    # appliance/server abstractions.
    precondition {
      condition     = length(local._servers_validation_invalid_oci_types) == 0
      error_message = "OCI servers must be type vm: ${join(", ", nonsensitive(local._servers_validation_invalid_oci_types))}"
    }

    precondition {
      condition     = length(local._servers_validation_invalid_parents) == 0
      error_message = "Invalid parent references found in servers configuration: ${join(", ", nonsensitive(local._servers_validation_invalid_parents))}"
    }

    precondition {
      condition     = length(local._servers_validation_invalid_types) == 0
      error_message = "Invalid server types found: ${join(", ", nonsensitive(local._servers_validation_invalid_types))}"
    }

    precondition {
      condition = length(local._servers_validation_key_mismatches) == 0

      error_message = (
        "Server YAML filenames must match the derived key (region for region roots, parent-name when parent is set, otherwise region-name): ${join(", ", local._servers_validation_key_mismatches)}"
      )
    }

    # OpenTofu locals are not generally recursive; keep the supported inheritance
    # depth explicit so addressing behavior remains predictable.
    precondition {
      condition     = length(local._servers_validation_long_parent_chains) == 0
      error_message = "Server parent inheritance supports at most two parent levels: ${join(", ", nonsensitive(local._servers_validation_long_parent_chains))}"
    }

    # OCI Always Free quota enforcement. Only checked when var.integrations.oci.always_free is true.
    precondition {
      error_message = "OCI VM shape must be Always Free eligible (VM.Standard.A1.Flex or VM.Standard.E2.1.Micro): ${join(", ", nonsensitive(local._servers_validation_oci_always_free_shapes_invalid))}"

      condition = (
        !var.integrations.oci.always_free ||
        length(local._servers_validation_oci_always_free_shapes_invalid) == 0
      )
    }

    precondition {
      error_message = "Always Free A1 Flex total OCPUs must not exceed 4 (got ${nonsensitive(local._servers_validation_oci_always_free_a1_cpus)})."

      condition = (
        !var.integrations.oci.always_free ||
        local._servers_validation_oci_always_free_a1_cpus <= 4
      )
    }

    precondition {
      error_message = "Always Free A1 Flex total memory must not exceed 24 GB (got ${nonsensitive(local._servers_validation_oci_always_free_a1_memory)} GB)."

      condition = (
        !var.integrations.oci.always_free ||
        local._servers_validation_oci_always_free_a1_memory <= 24
      )
    }

    precondition {
      error_message = "Always Free Micro instances must not exceed 2 (got ${nonsensitive(local._servers_validation_oci_always_free_micro_instances)})."

      condition = (
        !var.integrations.oci.always_free ||
        local._servers_validation_oci_always_free_micro_instances <= 2
      )
    }

    precondition {
      error_message = "Always Free total boot volume size must not exceed 200 GB (got ${nonsensitive(local._servers_validation_oci_always_free_boot_volume_gbs)} GB)."

      condition = (
        !var.integrations.oci.always_free ||
        local._servers_validation_oci_always_free_boot_volume_gbs <= 200
      )
    }

    precondition {
      condition     = length(local._servers_validation_oci_ingress_rule_names_not_unique) == 0
      error_message = "OCI ingress rule names must be unique per server: ${join(", ", nonsensitive(local._servers_validation_oci_ingress_rule_names_not_unique))}"
    }

    precondition {
      condition     = length(local._servers_validation_oci_ingress_rules_invalid) == 0
      error_message = "OCI ingress rules must use valid CIDRs, matching ICMP address families, and ordered port ranges: ${join(", ", nonsensitive(local._servers_validation_oci_ingress_rules_invalid))}"
    }

    # Catch short cycles before inherited address lookup hides the root cause.
    precondition {
      condition = length(local._servers_validation_parent_cycles) == 0

      error_message = (
        "Server parent references contain a cycle within the supported parent depth: ${join(", ", local._servers_validation_parent_cycles)}"
      )
    }

    precondition {
      condition     = length(local._servers_validation_routes_ids_not_unique) == 0
      error_message = "Server routing IDs must be unique per server: ${join(", ", nonsensitive(local._servers_validation_routes_ids_not_unique))}"
    }

    precondition {
      condition     = length(local._servers_validation_routes_invalid_proxies) == 0
      error_message = "Server routing proxy targets must reference an existing server: ${join(", ", nonsensitive(local._servers_validation_routes_invalid_proxies))}"
    }

    precondition {
      condition     = length(local._servers_validation_routes_missing_backend) == 0
      error_message = "Server routes require a shared or per-route backend_url: ${join(", ", nonsensitive(local._servers_validation_routes_missing_backend))}"
    }

    precondition {
      condition     = length(local._servers_validation_routes_not_unique) == 0
      error_message = "Server route hosts must be unique per server: ${join(", ", nonsensitive(local._servers_validation_routes_not_unique))}"
    }

    precondition {
      condition     = length(local._servers_validation_routes_unmanaged) == 0
      error_message = "Server route hosts must be in a managed DNS zone (data/dns/): ${join(", ", nonsensitive(local._servers_validation_routes_unmanaged))}"
    }

    precondition {
      condition     = length(local._servers_validation_self_parents) == 0
      error_message = "Servers cannot set themselves as their own parent: ${join(", ", nonsensitive(local._servers_validation_self_parents))}"
    }
  }
}
