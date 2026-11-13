data "tailscale_devices" "all" {}

locals {
  tailscale_address_ranges = {
    ipv4 = "100.64.0.0/10"
    ipv6 = "fd7a:115c:a1e0::/48"
  }

  tailscale_cluster_addresses = {
    for name, cluster in local.clusters : name => {
      ipv4 = one([for address in tailscale_service.cluster_ingress[name].addrs : address if can(cidrnetmask("${address}/32"))])
      ipv6 = one([for address in tailscale_service.cluster_ingress[name].addrs : address if startswith(address, "fd7a:")])
    }
  }

  # Each internal node's Tailscale serves the cluster's ingress Service and forwards it to Traefik.
  tailscale_cluster_serve_configs = {
    for name, cluster in local.clusters : name => jsonencode({
      Services = {
        "svc:${cluster.tailscale_ingress_service}" = {
          TCP = {
            for port in [80, 443] : tostring(port) => { TCPForward = "${cluster.tailscale_ingress_target}:${port}" }
          }
        }
      }
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

  tailscale_key_machines = {
    for name, machine in local.machines : name => machine
    if can(local.machine_tailscale_names[name]) && try(machine.type, null) != null
  }

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

    grants    = local.access.tailscale.grants
    groups    = local.access.tailscale.groups
    tagOwners = local.tailscale_tag_owners
    hosts = merge([
      for name in keys(local.clusters) : {
        (name)           = "${local.tailscale_cluster_addresses[name].ipv4}/32"
        ("${name}-ipv6") = "${local.tailscale_cluster_addresses[name].ipv6}/128"
      }
    ]...)
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
  description = "GitHub Actions"
  issuer      = "https://token.actions.githubusercontent.com"
  scopes      = ["auth_keys"]
  subject     = "repo:maxexcloo@927210/signtools-builder@1419923484:ref:refs/heads/main"
  tags        = ["tag:ephemeral"]

  depends_on = [tailscale_acl.default]
}

resource "tailscale_oauth_client" "fly" {
  # Replace this client when changing tags; successful updates may not persist them.
  description = "Fly"
  scopes      = ["auth_keys"]
  tags        = ["tag:ephemeral"]

  depends_on = [tailscale_acl.default]
}

resource "tailscale_service" "cluster_ingress" {
  for_each = local.clusters

  name  = "svc:${each.value.tailscale_ingress_service}"
  ports = ["tcp:80", "tcp:443"]
  tags  = ["tag:cluster-${each.key}"]
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
