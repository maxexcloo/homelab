data "tailscale_devices" "all" {}

locals {
  # Rules are ordered by least to most permissive source.
  tailscale_acls = [
    # Ephemeral: health checks, ping, and dashboard traffic only
    {
      action = "accept"
      dst    = ["tag:appliance:80", "tag:appliance:443"]
      src    = ["tag:ephemeral"]
    },
    {
      action = "accept"
      dst    = ["tag:router:*"]
      src    = ["tag:ephemeral"]
    },
    {
      action = "accept"
      dst    = ["tag:server:80", "tag:server:443"]
      src    = ["tag:ephemeral"]
    },
    {
      action = "accept"
      dst    = ["tag:vm:80", "tag:vm:443"]
      src    = ["tag:ephemeral"]
    },

    # VMs: service traffic and agent communication
    {
      action = "accept"
      dst    = ["tag:appliance:80", "tag:appliance:443"]
      src    = ["tag:vm"]
    },
    {
      action = "accept"
      dst    = ["tag:server:80", "tag:server:443", "tag:server:8120"]
      src    = ["tag:vm"]
    },
    {
      action = "accept"
      dst    = ["tag:vm:80", "tag:vm:443", "tag:vm:8120"]
      src    = ["tag:vm"]
    },

    # Servers: dashboard traffic to routers; full access to managed VMs,
    # appliances, and peer servers.
    {
      action = "accept"
      dst    = ["tag:router:80", "tag:router:443"]
      src    = ["tag:server"]
    },
    {
      action = "accept"
      dst    = ["tag:appliance:*"]
      src    = ["tag:server"]
    },
    {
      action = "accept"
      dst    = ["tag:server:*"]
      src    = ["tag:server"]
    },
    {
      action = "accept"
      dst    = ["tag:vm:*"]
      src    = ["tag:server"]
    },

    # Router: unrestricted as network gateway
    {
      action = "accept"
      dst    = ["*:*"]
      src    = ["tag:router"]
    },

    # Admin: unrestricted access from all personal devices and passkeys
    {
      action = "accept"
      dst    = ["*:*"]
      src    = ["group:admin"]
    },
  ]

  # Device names are matched back to server slugs; only the first IPv4/IPv6
  # address of each family is used for generated internal DNS records.
  tailscale_device_addresses = {
    for device in data.tailscale_devices.all.devices : split(".", device.name)[0] => {
      address = device.name
      id      = try(device.id, null)
      ipv4    = try([for address in device.addresses : address if can(cidrhost("${address}/32", 0))][0], null)
      ipv6    = try([for address in device.addresses : address if can(cidrhost("${address}/128", 0))][0], null)
    }
  }

  # tagOwners object for every generated server type tag.
  tailscale_tags = {
    for tag in sort(distinct([
      for server_type in values(local.defaults.server_types) : "tag:${server_type.tailscale_tag}"
    ])) : tag => ["group:admin"]
  }

  # autoApprovers object for generated exit node and subnet route approvals.
  tailscale_tags_approvers = {
    exitNode = sort(distinct([
      for type_key, type in local.defaults.server_types : "tag:${type.tailscale_tag}"
      if !contains(local.defaults.tailscale.approver_excludes, type_key)
    ]))

    routes = {
      for route in ["0.0.0.0/0", "::/0"] : route => sort(distinct([
        for type_key, type in local.defaults.server_types : "tag:${type.tailscale_tag}"
        if !contains(local.defaults.tailscale.approver_excludes, type_key)
      ]))
    }
  }
}

resource "tailscale_acl" "default" {
  acl = jsonencode({
    acls          = local.tailscale_acls
    autoApprovers = local.tailscale_tags_approvers
    tagOwners     = local.tailscale_tags

    groups = {
      "group:admin" = local.defaults.tailscale.admin_identities
    }
  })
}

resource "tailscale_tailnet_key" "server" {
  for_each = local.servers_by_feature.tailscale

  description   = each.key
  preauthorized = true
  reusable      = true
  tags          = ["tag:${each.value.type}"]

  depends_on = [
    tailscale_acl.default,
  ]
}

resource "tailscale_tailnet_key" "service" {
  for_each = local.services_by_feature.tailscale

  description   = each.key
  ephemeral     = true
  preauthorized = true
  reusable      = true
  tags          = ["tag:ephemeral"]

  depends_on = [
    tailscale_acl.default,
  ]
}
