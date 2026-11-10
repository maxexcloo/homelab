# Answer AAAA with :: so Tailscale clients use the machine's Tailscale IPv4 address.
resource "controld_custom_rule" "service" {
  for_each = merge([
    for machine_name, machine in local.machines : {
      for service_name, service in try(machine.services, {}) : "${machine_name}/${service_name}" => {
        hostname = service.hostname
        via      = local.tailscale_device_addresses[local.machine_tailscale_names[machine_name]].ipv4
      }
      if try(service.dns_tailscale, false)
    }
  ]...)

  do         = 2
  hostname   = each.value.hostname
  profile_id = local.provider_settings.providers.control_d.tailscale_profile
  status     = true
  via        = each.value.via
  via_v6     = "::"
}
