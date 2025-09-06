data "tailscale_devices" "default" {}

locals {
  # Create a map of device addresses indexed by device name
  tailscale_device_addresses = {
    for device in data.tailscale_devices.default.devices : split(".", device.name)[0] => {
      ipv4 = try([for a in device.addresses : a if can(cidrhost("${a}/32", 0))][0], null)
      ipv6 = try([for a in device.addresses : a if can(cidrhost("${a}/128", 0))][0], null)
    }
  }
}

resource "tailscale_tailnet_key" "caddy" {
  for_each = {
    for k, v in local.homelab_discovered : k => v
    if local.homelab_resources[k].docker
  }

  description   = "${each.key}-caddy"
  ephemeral     = true
  preauthorized = true
  reusable      = true
  tags          = ["tag:ephemeral"]
}

resource "tailscale_tailnet_key" "homelab" {
  for_each = {
    for k, v in local.homelab_discovered : k => v
    if local.homelab_resources[k].tailscale
  }

  description   = each.key
  preauthorized = true
  reusable      = true
  tags          = ["tag:${each.value.platform}"]
}
