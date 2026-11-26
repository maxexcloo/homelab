data "tailscale_devices" "all" {}

locals {
  tailscale_cluster_addresses = {
    for name, cluster in local.clusters : name => {
      ipv4 = one([for address in tailscale_service.cluster_ingress[name].addrs : address if can(cidrnetmask("${address}/32"))])
      ipv6 = one([for address in tailscale_service.cluster_ingress[name].addrs : address if startswith(address, "fd7a:")])
    }
  }

  # Each internal node's Tailscale serves the cluster's ingress Service and any machine Services assigned to it.
  tailscale_cluster_serve_configs = {
    for name, cluster in local.clusters : name => jsonencode({
      Services = merge(
        {
          "svc:${cluster.tailscale_ingress_service}" = {
            TCP = {
              for port in [80, 443] : tostring(port) => { TCPForward = "${cluster.tailscale_ingress_target}:${port}" }
            }
          }
        },
        {
          for machine_name, service in local.tailscale_machine_services :
          tailscale_service.machine[machine_name].name => {
            TCP = {
              for port in service.ports : tostring(port) => {
                TCPForward = "${local.machine_private_ipv4_addresses[machine_name]}:${port}"
              }
            }
          }
          if service.cluster == name
        },
      )
    })
  }

  tailscale_device_addresses = {
    for hostname, device in local.tailscale_devices : hostname => {
      ipv4 = try(
        one([for address in device.addresses : address if can(cidrnetmask("${address}/32"))]),
        null,
      )
      ipv6 = try(
        one([for address in device.addresses : address if startswith(address, "fd7a:")]),
        null,
      )
    }
  }

  tailscale_devices = {
    for name, devices in local.tailscale_devices_by_name :
    name => one([
      for device in devices : device
      if "${device.last_seen}|${device.id}" == element(
        sort([for candidate in devices : "${candidate.last_seen}|${candidate.id}"]),
        length(devices) - 1,
      )
    ])
  }

  tailscale_devices_by_name = {
    for device in data.tailscale_devices.all.devices :
    regex("^[^.]+", device.name) => device...
  }

  tailscale_ipset_machines = toset([
    for name in keys(local.tailscale_monitoring_machine_ports) : name
    if local.machines[name].type == "workstation"
  ])

  tailscale_ipv4_cidr = "100.64.0.0/10"

  tailscale_key_machines = {
    for name, machine in local.machines : name => machine
    if can(local.machine_tailscale_names[name]) && machine.type != null
  }

  tailscale_machine_service_addresses = {
    for name in keys(local.tailscale_machine_services) : name => {
      ipv4 = one([for address in tailscale_service.machine[name].addrs : address if can(cidrnetmask("${address}/32"))])
      ipv6 = one([for address in tailscale_service.machine[name].addrs : address if startswith(address, "fd7a:")])
    }
  }

  tailscale_machine_services = {
    for name, machine in local.machines : name => {
      cluster = machine.tailscale.service_cluster
      ports   = [for port in sort(distinct([for service in values(machine.services) : format("%05d", service.port)])) : tonumber(port)]
    }
    if can(machine.tailscale.service_cluster)
  }

  # Gatus pings managed machines and probes their monitored or certificate-bearing services.
  tailscale_monitoring_machine_ports = {
    for name, machine in local.machines : name => [
      for port in sort(distinct([
        for service in values(local.machine_services) : format("%05d", service.port)
        if service.machine == name && (
          service.hostnames[0] == local.machine_fqdns[name] ||
          try(service.dns_tailscale, false) ||
          (try(service.dns_record, false) && !try(service.dns_lan, false))
        )
      ])) : tonumber(port)
    ]
    if machine.type != null && can(local.machine_tailscale_names[name])
  }

  tailscale_monitoring_types = toset([
    for name in keys(local.tailscale_monitoring_machine_ports) : local.machines[name].type
    if local.machines[name].type != "workstation"
  ])

  tailscale_policy = {
    autoApprovers = {
      exitNode = local.access.tailscale.auto_approvers.exit_node
      routes   = local.access.tailscale.auto_approvers.routes
      services = {
        for name in keys(local.clusters) : "tag:cluster-${name}" => distinct([
          for node in values(local.talos_nodes) : node.tailscale_tag if node.cluster == name
        ])
      }
    }

    grants = concat(
      [
        for grant in local.access.tailscale.grants : merge(
          { for key, value in grant : key => value if key != "cluster" },
          can(grant.cluster) ? {
            dst = [tailscale_service.cluster_ingress[grant.cluster].name]
          } : {},
        )
      ],
      [
        for type in sort(tolist(local.tailscale_monitoring_types)) : {
          dst = ["tag:${type}"]
          ip = concat(["icmp:*"], [
            for port in sort(distinct(flatten([
              for name, ports in local.tailscale_monitoring_machine_ports :
              [for port in ports : format("%05d", port)]
              if local.machines[name].type == type
            ]))) : "tcp:${tonumber(port)}"
          ])
          src = ["tag:monitoring"]
        }
      ],
      [
        for name in sort(tolist(local.tailscale_ipset_machines)) : {
          dst = ["ipset:${name}"]
          ip  = concat(["icmp:*"], [for port in local.tailscale_monitoring_machine_ports[name] : "tcp:${port}"])
          src = ["tag:monitoring"]
        }
      ],
      [
        for name, service in local.tailscale_machine_services : {
          dst = [tailscale_service.machine[name].name]
          ip  = [for port in service.ports : "tcp:${port}"]
          src = ["tag:monitoring"]
        }
        if try(local.machines[name].monitoring, true)
      ],
    )
    groups = local.access.tailscale.groups
    ipsets = {
      for name in local.tailscale_ipset_machines : "ipset:${name}" => compact([
        try(local.tailscale_device_addresses[local.machine_tailscale_names[name]].ipv4, null) != null ? (
          "add ${local.tailscale_device_addresses[local.machine_tailscale_names[name]].ipv4}/32"
        ) : null,
        try(local.tailscale_device_addresses[local.machine_tailscale_names[name]].ipv6, null) != null ? (
          "add ${local.tailscale_device_addresses[local.machine_tailscale_names[name]].ipv6}/128"
        ) : null,
      ])
    }
    tagOwners = local.tailscale_tag_owners
  }

  tailscale_tag_owners = merge(
    {
      for tag in local.access.tailscale.tags : tag => local.access.tailscale.default_tag_owners
    },
    {
      for name in keys(local.clusters) : "tag:cluster-${name}" => local.access.tailscale.default_tag_owners
    },
  )
}

resource "tailscale_acl" "default" {
  acl                        = jsonencode(local.tailscale_policy)
  overwrite_existing_content = false
  reset_acl_on_destroy       = false
}

resource "tailscale_federated_identity" "github" {
  description = local.access.tailscale.github_identity.description
  issuer      = local.access.tailscale.github_identity.issuer
  scopes      = local.access.tailscale.github_identity.scopes
  subject     = local.access.tailscale.github_identity.subject
  tags        = local.access.tailscale.github_identity.tags

  depends_on = [tailscale_acl.default]
}

resource "tailscale_oauth_client" "fly" {
  # Replace this client when changing tags; successful updates may not persist them.
  description = "Fly"
  scopes      = ["auth_keys"]
  tags        = ["tag:monitoring"]

  depends_on = [tailscale_acl.default]
}

resource "tailscale_service" "cluster_ingress" {
  for_each = local.clusters

  name  = "svc:${each.value.tailscale_ingress_service}"
  ports = ["tcp:80", "tcp:443"]
  tags  = ["tag:cluster-${each.key}"]
}

resource "tailscale_service" "machine" {
  for_each = local.tailscale_machine_services

  name  = "svc:${local.machine_hostnames[each.key]}"
  ports = [for port in each.value.ports : "tcp:${port}"]
  tags  = ["tag:cluster-${each.value.cluster}"]
}

resource "tailscale_tailnet_key" "server" {
  for_each = local.tailscale_key_machines

  description         = "Machine ${each.key} recovery bootstrap"
  expiry              = local.access.tailscale.key_expiry_seconds
  preauthorized       = true
  recreate_if_invalid = "always"
  reusable            = false
  tags                = ["tag:${each.value.type}"]

  depends_on = [tailscale_acl.default]
}

resource "tailscale_tailnet_key" "sidestore_vpn" {
  for_each = local.clusters

  description         = "Cluster ${each.key} SideStore VPN bootstrap"
  expiry              = local.access.tailscale.key_expiry_seconds
  preauthorized       = true
  recreate_if_invalid = "always"
  reusable            = false
  tags                = ["tag:cluster-${each.key}"]

  depends_on = [tailscale_acl.default]
}

resource "tailscale_tailnet_key" "talos_container" {
  for_each = local.truenas_talos_containers

  description         = "Talos container bootstrap"
  expiry              = local.access.tailscale.key_expiry_seconds
  preauthorized       = true
  recreate_if_invalid = "never"
  reusable            = false
  tags                = [each.value.tailscale_tag]

  depends_on = [tailscale_acl.default]
}
