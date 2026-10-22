data "tailscale_devices" "all" {}

data "tailscale_service" "cluster_ingress" {
  for_each = {
    for name, cluster in local.clusters : name => cluster.tailscale_ingress_service
    if try(cluster.tailscale_ingress_service, null) != null
  }

  name = "svc:${each.value}"
}

locals {
  tailscale_address_ranges = {
    ipv4 = "100.64.0.0/10"
    ipv6 = "fd7a:115c:a1e0::/48"
  }

  tailscale_cluster_addresses = {
    for name, cluster in local.clusters : name => {
      ipv4 = try(
        one([for address in data.tailscale_service.cluster_ingress[name].addrs : address if can(cidrnetmask("${address}/32"))]),
        local.tailscale_device_addresses[name].ipv4,
      )
      ipv6 = try(cluster.tailscale_ingress_ipv6, true) ? try(
        one([for address in data.tailscale_service.cluster_ingress[name].addrs : address if startswith(address, "fd7a:")]),
        local.tailscale_device_addresses[name].ipv6,
      ) : null
    }
  }

  tailscale_cluster_devices_by_hostname = {
    for device in data.tailscale_devices.all.devices : device.hostname => device...
    if can(local.clusters[device.hostname])
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
    for name, devices in merge(local.tailscale_devices_by_name, local.tailscale_cluster_devices_by_hostname) :
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

  tailscale_key_machines = {
    for name, machine in local.machines : name => machine
    if can(local.machine_tailscale_names[name]) && try(machine.type, null) != null
  }

  tailscale_machine_device_names = {
    for machine_name, desired_name in local.machine_tailscale_names :
    machine_name => (
      can(local.tailscale_devices_by_name[desired_name]) ? desired_name :
      can(local.tailscale_devices_by_name[machine_name]) ? machine_name :
      desired_name
    )
  }

  tailscale_policy = {
    autoApprovers = {
      exitNode = local.access.tailscale.auto_approvers.exit_node
      routes = merge(
        local.access.tailscale.auto_approvers.routes,
        local.tailscale_route_approvers,
      )
      services = {
        for name in keys(local.clusters) : "tag:cluster-${name}" => ["tag:cluster-${name}"]
      }
    }

    grants    = local.access.tailscale.grants
    groups    = local.access.tailscale.groups
    tagOwners = local.tailscale_tag_owners
    hosts = merge([
      for name in keys(local.clusters) : merge(
        { (name) = "${local.tailscale_cluster_addresses[name].ipv4}/32" },
        local.tailscale_cluster_addresses[name].ipv6 != null ? {
          ("${name}-ipv6") = "${local.tailscale_cluster_addresses[name].ipv6}/128"
        } : {},
      )
    ]...)
  }

  tailscale_route_approvers = {
    for route in toset(flatten([
      for node in values(local.talos_nodes) : node.tailscale_routes
      ])) : route => distinct(compact([
      for node_name, node in local.talos_nodes :
      contains(node.tailscale_routes, route) ? try(node.tailscale_tag, "tag:${local.machines[node_name].type}") : null
    ]))
  }

  tailscale_tag_owners = merge(
    {
      for tag in local.access.tailscale.tags : tag => local.access.tailscale.default_tag_owners
    },
    {
      for name in keys(local.clusters) : "tag:cluster-${name}" => concat(local.access.tailscale.default_tag_owners, ["tag:cluster-${name}-operator"])
    },
    {
      for name in keys(local.clusters) : "tag:cluster-${name}-operator" => local.access.tailscale.default_tag_owners
    },
  )
}

resource "tailscale_acl" "default" {
  acl                        = jsonencode(local.tailscale_policy)
  overwrite_existing_content = false
  reset_acl_on_destroy       = false
}

resource "tailscale_federated_identity" "github" {
  description = "GitHub Actions"
  issuer      = "https://token.actions.githubusercontent.com"
  scopes      = ["auth_keys"]
  subject     = "repo:maxexcloo@927210/signtools-builder@1419923484:ref:refs/heads/main"
  tags        = ["tag:ephemeral"]

  depends_on = [tailscale_acl.default]
}

resource "tailscale_oauth_client" "fly" {
  description = "Fly"
  scopes      = ["auth_keys"]
  tags        = ["tag:fly"]

  depends_on = [tailscale_acl.default]
}

resource "tailscale_oauth_client" "kubernetes_operator" {
  for_each = local.clusters

  description = "Cluster ${each.key} Kubernetes operator"
  scopes      = local.access.tailscale.operator.scopes
  tags        = ["tag:cluster-${each.key}-operator"]

  depends_on = [tailscale_acl.default]
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

resource "tailscale_tailnet_key" "talos_container" {
  description         = "Talos container bootstrap"
  expiry              = local.access.tailscale.key_expiry_seconds
  preauthorized       = true
  recreate_if_invalid = "never"
  reusable            = false
  tags                = [local.truenas_talos_container.tailscale_tag]

  depends_on = [tailscale_acl.default]
}
