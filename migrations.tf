# Adopt the existing zone-based firewall policies; the configuration matches the live policies.
# Remove this file once the imports are in state.
import {
  to = unifi_firewall_policy.configured["internal_iot"]
  id = "68959311f8f0702f9177b484"
}

import {
  to = unifi_firewall_policy.configured["iot_haos"]
  id = "6944b4ac254b3c1a8aa2deac"
}

import {
  to = unifi_firewall_policy.configured["vpn_iot"]
  id = "6895934ff8f0702f9177b674"
}
