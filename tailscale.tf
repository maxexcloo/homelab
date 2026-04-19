data "tailscale_devices" "all" {}

locals {
  # Device names are matched back to server slugs; only the first IPv4/IPv6
  # address of each family is used for generated internal DNS records.
  tailscale_device_addresses = {
    for device in data.tailscale_devices.all.devices : split(".", device.name)[0] => {
      ipv4 = try([for a in device.addresses : a if can(cidrhost("${a}/32", 0))][0], null)
      ipv6 = try([for a in device.addresses : a if can(cidrhost("${a}/128", 0))][0], null)
    }
  }

  # Route auto-approvers exclude appliance and ephemeral tags because those
  # nodes should not become subnet routers or exit nodes.
  tailscale_route_tags = toset([
    for tag in local.defaults.tailscale.tags : "tag:${tag}"
    if !contains(["appliance", "ephemeral"], tag)
  ])

  # Full tag set used for ACL ownership declarations.
  tailscale_tags = toset([
    for tag in local.defaults.tailscale.tags : "tag:${tag}"
  ])
}

resource "tailscale_acl" "default" {
  acl = jsonencode({
    # Rules: ordered by least to most permissive source
    acls = [
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

      # Servers: full access to managed VMs, appliances, and peer servers
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
      }
    ]

    # Exit nodes and subnet routes: routers, servers, and VMs may optionally advertise
    autoApprovers = {
      exitNode = tolist(local.tailscale_route_tags)
      routes = {
        "0.0.0.0/0" = tolist(local.tailscale_route_tags)
        "::/0"      = tolist(local.tailscale_route_tags)
      }
    }

    groups = {
      "group:admin" = local.defaults.tailscale.admin_identities
    }

    tagOwners = {
      for tag in local.tailscale_tags : tag => ["group:admin"]
    }
  })
}

resource "tailscale_tailnet_key" "server" {
  for_each = local.servers_by_feature.tailscale

  description   = each.key
  preauthorized = true
  reusable      = true
  tags          = ["tag:${each.value.type}"]

  depends_on = [tailscale_acl.default]
}

resource "tailscale_tailnet_key" "service" {
  for_each = local.services_by_feature.tailscale

  description   = each.key
  ephemeral     = true
  preauthorized = true
  reusable      = true
  tags          = ["tag:ephemeral"]

  depends_on = [tailscale_acl.default]
}
