# Import blocks for existing Incus instances
# Format: "remote_name/instance_name"
# Remote names come from incus_servers local (server IDs with platform=incus and type=server)

import {
  to = incus_instance.vm["au-pie-cyberpower-vp1000lcd"]
  id = "au-pie:default/cyberpower-vp1000lcd,image=images:ubuntu/24.04"
}

import {
  to = incus_instance.vm["au-pie-haos"]
  id = "au-pie:default/haos"
}

import {
  to = incus_instance.vm["au-pie-truenas"]
  id = "au-pie:default/truenas"
}
