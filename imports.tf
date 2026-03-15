# Import blocks for existing Incus instances
# Format: "remote_name/instance_name"
# Remote names come from incus_servers local (server IDs with platform=incus and type=server)

import {
  to = incus_instance.vm["au-pie-cyberpower"]
  id = "default/cyberpower"
}

import {
  to = incus_instance.vm["au-pie-haos"]
  id = "default/haos"
}

import {
  to = incus_instance.vm["au-pie-truenas"]
  id = "default/truenas"
}
