data "tailscale_devices" "all" {}

locals {
  tailscale_device_addresses = {
    for device in data.tailscale_devices.all.devices : split(".", device.name)[0] => {
      ipv4 = try([for a in device.addresses : a if can(cidrhost("${a}/32", 0))][0], null)
      ipv6 = try([for a in device.addresses : a if can(cidrhost("${a}/128", 0))][0], null)
    }
  }

  tailscale_tags = toset([
    for k, v in local.servers_by_feature.tailscale : "tag:${v.type}"
  ])
}

resource "tailscale_acl" "default" {
  acl = jsonencode({
    # Rules: ordered by least to most permissive source
    acls = [
      # Ephemeral: health checks, ping, and dashboard traffic only
      {
        action = "accept"
        dst    = ["tag:router:0"]
        src    = ["tag:ephemeral"]
      },
      {
        action = "accept"
        dst    = ["tag:server:0", "tag:server:80", "tag:server:443"]
        src    = ["tag:ephemeral"]
      },
      {
        action = "accept"
        dst    = ["tag:vm:0", "tag:vm:80", "tag:vm:443"]
        src    = ["tag:ephemeral"]
      },

      # VMs: service traffic and Komodo agent communication
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

      # Servers: full access to managed VMs and peer servers
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

    # Exit nodes and subnet routes: any tagged device may optionally advertise
    autoApprovers = {
      exitNode = tolist(local.tailscale_tags)
      routes = {
        "0.0.0.0/0" = tolist(local.tailscale_tags)
        "::/0"      = tolist(local.tailscale_tags)
      }
    }

    # Identity
    groups = {
      "group:admin" = concat([local.defaults.email], var.tailscale_admin_identities)
    }

    tagOwners = {
      for tag in concat(tolist(local.tailscale_tags), ["tag:ephemeral"]) : tag => ["group:admin"]
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
