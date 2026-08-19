data "tailscale_devices" "all" {}

locals {
  tailscale_cluster_tags = toset([
    for name in keys(local.clusters) : "tag:${name}"
  ])

  tailscale_device_ipv4 = {
    for device in data.tailscale_devices.all.devices :
    regex("^[^.]+", device.name) => try(
      one([for address in device.addresses : address if can(cidrnetmask("${address}/32"))]),
      null,
    )
  }

  tailscale_device_ipv6 = {
    for device in data.tailscale_devices.all.devices :
    regex("^[^.]+", device.name) => try(
      one([for address in device.addresses : address if startswith(address, "fd7a:")]),
      null,
    )
  }

  tailscale_operator_client_tags = {
    for name in keys(local.clusters) : name => ["tag:${name}-operator"]
  }

  tailscale_routes = toset(flatten([
    for cluster in values(local.clusters) : flatten([
      for node in values(cluster.nodes) : try(node.tailscale_routes, [])
    ])
  ]))

  tailscale_policy = {
    acls = concat(
      local.access.tailscale.acls,
      [
        for tag in local.tailscale_cluster_tags : {
          action = "accept"
          dst    = ["*:*"]
          src    = [tag]
        }
      ],
    )

    autoApprovers = {
      exitNode = local.access.tailscale.auto_approvers.exit_node
      routes = merge(
        local.access.tailscale.auto_approvers.routes,
        {
          for route in local.tailscale_routes : route => ["tag:talos"]
        },
      )
    }

    groups = local.access.tailscale.groups

    tagOwners = merge(
      local.access.tailscale.tag_owners,
      {
        for tag in local.tailscale_cluster_tags : tag => [tag, "group:admin"]
      },
      {
        for tag in local.tailscale_cluster_tags : "${tag}-operator" => [tag]
      },
    )

    tests = local.access.tailscale.tests
  }
}

resource "tailscale_acl" "default" {
  acl                        = jsonencode(local.tailscale_policy)
  overwrite_existing_content = false
  reset_acl_on_destroy       = false
}

resource "tailscale_oauth_client" "kubernetes_operator" {
  for_each = local.clusters

  description = "${each.key} Kubernetes operator"
  scopes      = local.access.tailscale.operator.scopes
  tags        = local.tailscale_operator_client_tags[each.key]

  depends_on = [tailscale_acl.default]
}

resource "tailscale_tailnet_key" "server" {
  for_each = local.machines

  description         = "${each.key} recovery bootstrap"
  expiry              = local.access.tailscale.key_expiry_seconds
  preauthorized       = true
  recreate_if_invalid = "always"
  reusable            = true
  tags                = ["tag:${each.value.tailscale_tag}"]

  depends_on = [tailscale_acl.default]
}
