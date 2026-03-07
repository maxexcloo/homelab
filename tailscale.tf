data "tailscale_devices" "default" {}

locals {
  tailscale_device_addresses = {
    for device in data.tailscale_devices.default.devices : split(".", device.name)[0] => {
      ipv4 = try([for a in device.addresses : a if can(cidrhost("${a}/32", 0))][0], null)
      ipv6 = try([for a in device.addresses : a if can(cidrhost("${a}/128", 0))][0], null)
    }
  }
}

resource "tailscale_tailnet_key" "server" {
  for_each = {
    for k, v in local._servers : k => v
    if v.enable_tailscale
  }

  description   = each.key
  preauthorized = true
  reusable      = true
  tags          = ["tag:${each.value.type}"]
}

resource "tailscale_tailnet_key" "service" {
  for_each = local.services_instances

  description   = each.key
  preauthorized = true
  reusable      = true
  tags          = ["tag:ephemeral"]
}
