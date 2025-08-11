data "tailscale_devices" "default" {}

locals {
  tailscale_device_map = {
    for device in data.tailscale_devices.default.devices : split(".", device.name)[0] => device
    if length(split(".", device.name)) > 0
  }

  tailscale_devices = {
    for k, v in local.homelab_discovered : k => {
      tailscale_ipv4 = try([for address in local.tailscale_device_map[v.title].addresses : address if can(cidrhost("${address}/32", 0))][0], null)
      tailscale_ipv6 = try([for address in local.tailscale_device_map[v.title].addresses : address if can(cidrhost("${address}/128", 0))][0], null)
    }
    if contains(keys(local.tailscale_device_map), v.title)
  }
}


resource "tailscale_tailnet_key" "homelab" {
  for_each = {
    for k, v in local.homelab_discovered : k => v
    if contains(local.homelab_flags[k].resources, "tailscale")
  }

  description   = each.key
  preauthorized = true
  reusable      = true
  tags          = ["tag:${each.value.platform}"]
}
