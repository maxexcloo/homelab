# Talos workers moved to Podman Quadlets delivered by `mise run hosts:sync`. The
# provider stays until state forgets the containers, which keep running until
# their host is migrated.
provider "docker" {
  for_each = local.sync_hosts

  alias                       = "hosts"
  disable_docker_daemon_check = true
  host                        = "ssh://${each.value.username}@${local.machine_fqdns[each.key]}"
}

removed {
  from = docker_container.talos

  lifecycle {
    destroy = false
  }
}

removed {
  from = docker_container.talos_tailscale

  lifecycle {
    destroy = false
  }
}

removed {
  from = docker_image.talos

  lifecycle {
    destroy = false
  }
}

removed {
  from = docker_image.talos_tailscale

  lifecycle {
    destroy = false
  }
}

removed {
  from = docker_network.talos_local

  lifecycle {
    destroy = false
  }
}

removed {
  from = docker_network.talos_services

  lifecycle {
    destroy = false
  }
}
