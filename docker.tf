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

# Privileged, so GPU pods see the host's /dev/dri and /dev/kfd. Public DNS keeps
# private service names on their Tailscale records rather than UniFi LAN overrides.
resource "docker_container" "talos" {
  for_each = local.docker_talos_containers

  cgroupns_mode = "private"
  dns           = ["1.1.1.1", "1.0.0.1"]
  env           = ["PLATFORM=container"]
  hostname      = each.value.name
  image         = docker_image.talos[each.key].image_id
  name          = each.value.app_name
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
      volume_name    = "${each.value.app_name}-${volumes.value}"
    }
  }
}

resource "docker_container" "talos_tailscale" {
  for_each = local.docker_talos_containers

  env = [
    "TS_AUTHKEY=${tailscale_tailnet_key.talos_container[each.key].key}",
    "TS_AUTH_ONCE=true",
    "TS_EXTRA_ARGS=--accept-dns=false",
    "TS_HOSTNAME=${each.value.device_name}",
    "TS_ROUTES=${join(",", each.value.tailscale_routes)}",
    "TS_STATE_DIR=/var/lib/tailscale",
    "TS_USERSPACE=false",
  ]
  image        = docker_image.talos_tailscale[each.key].image_id
  name         = "${each.value.app_name}-tailscale"
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
    container_path = "/var/lib/tailscale"
    volume_name    = "${each.value.app_name}-tailscale"
  }
}

resource "docker_image" "talos" {
  for_each = local.docker_talos_containers

  keep_locally = true
  name         = "ghcr.io/siderolabs/talos:${local.clusters[each.value.cluster].talos_version}"
  provider     = docker.hosts[each.key]
}

resource "docker_image" "talos_tailscale" {
  for_each = local.docker_talos_containers

  keep_locally = true
  name         = local.talos_container_tailscale_image
  provider     = docker.hosts[each.key]
}

resource "docker_network" "talos_local" {
  for_each = local.docker_talos_containers

  driver   = "bridge"
  internal = true
  name     = "${each.value.app_name}-local"
  provider = docker.hosts[each.key]
}

resource "docker_network" "talos_services" {
  for_each = local.docker_talos_containers

  driver   = "macvlan"
  name     = "${each.value.app_name}-services"
  provider = docker.hosts[each.key]

  options = {
    parent = each.value.interface
  }

  ipam_config {
    gateway = cidrhost(local.unifi_networks[each.value.network_key].subnet, 1)
    subnet  = cidrsubnet(local.unifi_networks[each.value.network_key].subnet, 0, 0)
  }
}
