# Import blocks for existing Incus resources
# Format: "remote_name/instance_name"
# Remote names come from incus_servers local (server IDs with platform=incus and type=server)

# Incus Profiles - Format: "remote:project/profile_name"
import {
  to = incus_profile.profile["default:au-pie"]
  id = "au-pie:default/default"
}

import {
  to = incus_profile.profile["default:au-malatang"]
  id = "au-malatang:default/default"
}

# Incus Projects - Format: "remote:project_name"
import {
  to = incus_project.project["default:au-pie"]
  id = "au-pie:default"
}

import {
  to = incus_project.project["default:au-malatang"]
  id = "au-malatang:default"
}

# Incus Instances
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
