locals {
  tailscale_policy = {
    groups = {
      "group:${local.access.tailscale.admin_group}" = local.tailscale_admin_identities
    }

    tagOwners = merge(
      {
        for tag in local.tailscale_host_tags : tag => ["group:${local.access.tailscale.admin_group}"]
      },
      {
        for tag in values(local.tailscale_operator_tags) : "tag:${tag}" => ["group:${local.access.tailscale.admin_group}"]
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
        for tag in values(local.tailscale_operator_tags) : {
          action = "accept"
          src    = ["tag:${tag}"]
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

resource "tailscale_tailnet_key" "server" {
  for_each = local.machines

  description         = "${each.key} recovery bootstrap"
  expiry              = local.tailscale_key_expiry
  preauthorized       = true
  recreate_if_invalid = "always"
  reusable            = true
  tags                = ["tag:${each.value.tailscale_tag}"]

  depends_on = [tailscale_acl.default]
}

resource "tailscale_oauth_client" "kubernetes_operator" {
  for_each = local.clusters

  description = "${each.key} Kubernetes operator"
  scopes      = local.access.tailscale.operator.scopes
  tags        = ["tag:${local.tailscale_operator_tags[each.key]}"]

  depends_on = [tailscale_acl.default]
}
