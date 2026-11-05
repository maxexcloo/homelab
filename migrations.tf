# Adopt the existing zone-based firewall policies; the configuration matches the live policies.
import {
  for_each = local.provider_settings.providers.unifi.firewall_policies

  to = unifi_firewall_policy.configured[each.key]
  id = each.value.id
}
