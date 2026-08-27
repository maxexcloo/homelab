data "tailscale_devices" "all" {}

locals {
  tailscale_device_current = {
    for hostname, devices in local.tailscale_devices_by_hostname :
    hostname => one([
      for device in devices : device
      if "${device.last_seen}|${device.id}" == element(
        sort([for candidate in devices : "${candidate.last_seen}|${candidate.id}"]),
        length(devices) - 1,
      )
    ])
  }

  tailscale_device_ipv4 = merge(
    {
      for device in data.tailscale_devices.all.devices :
      regex("^[^.]+", device.name) => try(
        one([for address in device.addresses : address if can(cidrnetmask("${address}/32"))]),
        null,
      )
    },
    {
      for hostname, device in local.tailscale_device_current :
      hostname => try(
        one([for address in device.addresses : address if can(cidrnetmask("${address}/32"))]),
        null,
      )
    },
  )

  tailscale_device_ipv6 = merge(
    {
      for device in data.tailscale_devices.all.devices :
      regex("^[^.]+", device.name) => try(
        one([for address in device.addresses : address if startswith(address, "fd7a:")]),
        null,
      )
    },
    {
      for hostname, device in local.tailscale_device_current :
      hostname => try(
        one([for address in device.addresses : address if startswith(address, "fd7a:")]),
        null,
      )
    },
  )

  tailscale_devices_by_hostname = {
    for hostname in toset([
      for device in data.tailscale_devices.all.devices : device.hostname
      if contains(keys(local.clusters), device.hostname)
    ]) :
    hostname => [
      for device in data.tailscale_devices.all.devices : device
      if device.hostname == hostname
    ]
  }

  tailscale_routes = toset(flatten([
    for cluster in values(local.clusters) : [
      for node in values(cluster.nodes) : try(node.tailscale_routes, [])
    ]
  ]))

  tailscale_tags_cluster = toset([
    for name in keys(local.clusters) : "tag:${name}"
  ])

  tailscale_tags_cluster_all = flatten([
    for tag in local.tailscale_tags_cluster : [tag, "${tag}-operator"]
  ])

  tailscale_tags_cluster_conflicting = setintersection(
    toset(local.tailscale_tags_cluster_all),
    toset(keys(local.access.tailscale.tag_owners)),
  )

  tailscale_policy = {
    acls = local.access.tailscale.acls

    autoApprovers = {
      exitNode = local.access.tailscale.auto_approvers.exit_node
      routes = merge(
        local.access.tailscale.auto_approvers.routes,
        {
          for route in local.tailscale_routes : route => ["tag:kubernetes"]
        },
      )
    }

    groups = local.access.tailscale.groups

    tagOwners = merge(
      local.access.tailscale.tag_owners,
      {
        for tag in local.tailscale_tags_cluster : tag => ["${tag}-operator", "group:admin"]
      },
      {
        for tag in local.tailscale_tags_cluster : "${tag}-operator" => ["group:admin"]
      },
    )

    tests = local.access.tailscale.tests
  }
}

resource "tailscale_acl" "default" {
  acl                        = jsonencode(local.tailscale_policy)
  overwrite_existing_content = false
  reset_acl_on_destroy       = false

  depends_on = [terraform_data.tailscale_tag_validation]
}

resource "tailscale_oauth_client" "kubernetes_operator" {
  for_each = local.clusters

  description = "${each.key} Kubernetes operator"
  scopes      = local.access.tailscale.operator.scopes
  tags        = ["tag:${each.key}-operator"]

  depends_on = [tailscale_acl.default]
}

resource "tailscale_tailnet_key" "server" {
  for_each = local.machines

  description         = "${each.key} recovery bootstrap"
  expiry              = local.access.tailscale.key_expiry_seconds
  preauthorized       = true
  recreate_if_invalid = "always"
  reusable            = true
  tags                = ["tag:${each.value.tag}"]

  depends_on = [tailscale_acl.default]
}

resource "terraform_data" "tailscale_tag_validation" {
  input = sort(local.tailscale_tags_cluster_all)

  lifecycle {
    precondition {
      condition     = length(distinct(local.tailscale_tags_cluster_all)) == length(local.tailscale_tags_cluster_all)
      error_message = "Cluster and Kubernetes operator Tailscale tags must be unique."
    }

    precondition {
      condition     = length(local.tailscale_tags_cluster_conflicting) == 0
      error_message = "Generated cluster Tailscale tags must not overlap configured tag owners: ${join(", ", sort(tolist(local.tailscale_tags_cluster_conflicting)))}"
    }
  }
}
