locals {
  docker_hosts = {
    for name, machine in local.machines : name => machine
    if contains(["bazzite", "ucore"], machine.platform)
  }

  docker_talos_containers = {
    for name, container in local.talos_containers : name => merge(container, {
      interface = one([
        for interface in local.machines[name].interfaces : interface.name
        if cidrcontains(local.unifi_networks[container.network_key].subnet, interface.address)
      ])
    })
    if can(local.docker_hosts[name])
  }
}

# Privileged, so GPU pods see the host's /dev/dri and /dev/kfd.
resource "docker_container" "talos" {
  for_each = local.docker_talos_containers

  cgroupns_mode = "private"
  dns           = local.talos_container_dns_servers
  env           = ["PLATFORM=container"]
  hostname      = each.value.name
  image         = docker_image.talos[each.key].image_id
  name          = "talos"
  privileged    = true
  provider      = docker.hosts[each.key]
  read_only     = true
  restart       = "unless-stopped"
  security_opts = ["label=disable", "seccomp=unconfined"]

  tmpfs = {
    "/run"    = ""
    "/system" = ""
    "/tmp"    = ""
  }

  # macvlan cannot reach the host; the local bridge gives Tailscale a peer path.
  networks_advanced {
    name = docker_network.talos_local[each.key].name
  }

  networks_advanced {
    ipv4_address = each.value.address
    mac_address  = each.value.mac
    name         = docker_network.talos_services[each.key].name
  }

  # Host directories sit beside TrueNAS nodes' datasets, so pods share one hostPath root.
  dynamic "mounts" {
    for_each = toset(each.value.paths)

    content {
      source = mounts.value
      target = "/var/mnt/datasets/${basename(mounts.value)}"
      type   = "bind"

      bind_options {
        propagation = "rslave"
      }
    }
  }

  volumes {
    container_path = "/lib/modules"
    host_path      = "/lib/modules"
    read_only      = true
  }

  dynamic "volumes" {
    for_each = {
      "/opt"          = "opt"
      "/system/state" = "state"
      "/var"          = "var"
    }

    content {
      container_path = volumes.key
      volume_name    = "talos-${volumes.value}"
    }
  }
}

resource "docker_container" "talos_tailscale" {
  for_each = local.docker_talos_containers

  env = [
    for key, value in local.talos_container_tailscale_environment[each.key] : "${key}=${value}"
  ]
  image        = docker_image.talos_tailscale[each.key].image_id
  name         = "talos-tailscale"
  network_mode = "container:${docker_container.talos[each.key].id}"
  provider     = docker.hosts[each.key]
  restart      = "unless-stopped"

  capabilities {
    add = ["CAP_NET_ADMIN", "CAP_NET_RAW"]
  }

  devices {
    container_path = "/dev/net/tun"
    host_path      = "/dev/net/tun"
  }

  volumes {
    container_path = local.talos_container_tailscale_state_directory
    volume_name    = "talos-tailscale"
  }
}

resource "docker_image" "talos" {
  for_each = local.docker_talos_containers

  keep_locally = true
  name         = each.value.image
  provider     = docker.hosts[each.key]
}

resource "docker_image" "talos_tailscale" {
  for_each = local.docker_talos_containers

  keep_locally = true
  name         = local.images.tailscale
  provider     = docker.hosts[each.key]
}

resource "docker_network" "talos_local" {
  for_each = local.docker_talos_containers

  driver   = "bridge"
  internal = true
  name     = "talos-local"
  provider = docker.hosts[each.key]
}

resource "docker_network" "talos_services" {
  for_each = local.docker_talos_containers

  driver   = "macvlan"
  name     = "talos-services"
  provider = docker.hosts[each.key]

  options = {
    parent = each.value.interface
  }

  ipam_config {
    gateway = cidrhost(local.unifi_networks[each.value.network_key].subnet, 1)
    subnet  = cidrsubnet(local.unifi_networks[each.value.network_key].subnet, 0, 0)
  }
}
