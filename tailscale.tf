data "tailscale_devices" "all" {}

locals {
  tailscale_cluster_tags = toset([
    for name in keys(local.clusters) : "tag:${name}"
  ])

  tailscale_host_tags = toset(concat(
    [for machine in values(local.machines) : "tag:${machine.tailscale_tag}"],
    [for tag in local.access.tailscale.additional_tags : "tag:${tag}"],
  ))

  tailscale_routes = toset(flatten([
    for cluster in values(local.clusters) : flatten([
      for node in values(cluster.nodes) : try(node.tailscale_routes, [])
    ])
  ]))

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

  tailscale_policy = {
    groups = {
      "group:${local.access.tailscale.admin_group}" = local.access.tailscale.admin_identities
    }

    tagOwners = merge(
      {
        for tag in local.tailscale_host_tags : tag => ["group:${local.access.tailscale.admin_group}"]
      },
      {
        for tag in local.tailscale_cluster_tags : tag => [tag, "group:${local.access.tailscale.admin_group}"]
      },
      {
        for tag in local.tailscale_cluster_tags : "${tag}-operator" => [tag]
      },
    )

    autoApprovers = {
      exitNode = local.access.tailscale.exit_node_approver_tags
      routes = merge(
        local.access.tailscale.route_approvers,
        {
          for route in local.tailscale_routes : route => ["tag:${local.access.tailscale.route_approver_tag}"]
        },
      )
    }

    acls = concat(
      [for rule in local.access.tailscale.rules : merge(
        {
          action = rule.action
          src    = rule.sources
          dst    = rule.destinations
        },
        try(rule.protocol, null) == null ? {} : { proto = rule.protocol },
      )],
      [
        for tag in local.tailscale_cluster_tags : {
          action = "accept"
          src    = [tag]
          dst    = ["*:*"]
        }
      ],
    )

    tests = [for test in local.access.tailscale.tests : {
      src    = test.source
      accept = test.accept
    }]
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
