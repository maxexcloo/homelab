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
        "tag:${local.tailscale_operator_tag}" = ["group:${local.access.tailscale.admin_group}"]
      },
    )

    autoApprovers = {
      routes = {
        for route in local.tailscale_routes : route => ["tag:${local.access.tailscale.route_approver_tag}"]
      }
    }

    acls = [for rule in local.access.tailscale.rules : {
      action = rule.action
      src    = rule.sources
      dst    = rule.destinations
    }]

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

  # Adoption gate only: remove after the import in migrations.tf is recorded.
  lifecycle {
    ignore_changes = [
      acl,
      overwrite_existing_content,
      reset_acl_on_destroy,
    ]
  }
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
  tags        = ["tag:${local.tailscale_operator_tag}"]

  depends_on = [tailscale_acl.default]
}
