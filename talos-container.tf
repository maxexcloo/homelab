data "talos_machine_configuration" "container" {
  cluster_endpoint   = local.talos_cluster_endpoints[local.truenas_talos_container.cluster]
  cluster_name       = local.truenas_talos_container.cluster
  kubernetes_version = local.clusters[local.truenas_talos_container.cluster].kubernetes_version
  machine_secrets    = talos_machine_secrets.cluster[local.truenas_talos_container.cluster].machine_secrets
  machine_type       = local.truenas_talos_container.machine_type
  talos_version      = local.clusters[local.truenas_talos_container.cluster].talos_version

  config_patches = concat(
    [yamlencode(local.talos_user_volume_local_path_directory)],
    local.truenas_talos_container.machine_type == "controlplane" ? [yamlencode(local.talos_cluster_authentication_configuration)] : [],
    [
      # v1.14's standalone KubeletConfig does not expose extraMounts.
      yamlencode({ apiVersion = "v1alpha1", kind = "KubeletConfig", "$patch" = "delete" }),
      yamlencode({
        machine = {
          kubelet = {
            image = "ghcr.io/siderolabs/kubelet:${local.clusters[local.truenas_talos_container.cluster].kubernetes_version}"
            extraMounts = [{
              destination = "/var/mnt/datasets"
              options     = ["rbind", "rshared", "rw"]
              source      = "/var/mnt/datasets"
              type        = "bind"
            }]
            extraConfig = {
              # The stock kubelet image cannot report capacity for the host ZFS dataset.
              localStorageCapacityIsolation = false
              kubeReserved = {
                memory = "1Gi"
              }
              systemReserved = {
                memory = "${local.truenas_talos_container.host_memory_kib - local.truenas_talos_container.memory_gib * 1024 * 1024}Ki"
              }
            }
          }
        }
      }),
    ],
    [for document in local.talos_machine_configuration_documents_common[local.truenas_talos_container_host] : yamlencode(document)],
  )
}

locals {
  truenas_talos_container = merge(
    local.talos_nodes[local.truenas_talos_container_host],
    local.talos_nodes[local.truenas_talos_container_host].container,
    { name = local.machine_hostnames[local.truenas_talos_container_host] },
  )

  truenas_talos_container_host = one([
    for name, node in local.talos_nodes : name
    if node.configuration_delivery == "container"
  ])

  truenas_talos_container_network_key = local.unifi_clients[
    lower(local.truenas_hosts_services[local.truenas_talos_container_host].interface.mac_address)
  ].network_key

  truenas_talos_container_storage_path = truenas_dataset.root[
    "${local.truenas_talos_container_host}/${local.truenas_talos_container.app_name}"
  ].mount_point
}

resource "talos_machine_configuration_apply" "container" {
  apply_mode                     = "no_reboot"
  client_configuration_wo        = talos_machine_secrets.cluster[local.truenas_talos_container.cluster].client_configuration
  endpoint                       = local.truenas_talos_container.address
  machine_configuration_input_wo = data.talos_machine_configuration.container.machine_configuration
  node                           = local.truenas_talos_container.address

  on_destroy = {
    graceful = false
    reboot   = false
    reset    = false
  }

  depends_on = [truenas_app.talos_container]
}

resource "tailscale_tailnet_key" "container" {
  description         = "Talos container bootstrap"
  expiry              = local.access.tailscale.key_expiry_seconds
  preauthorized       = true
  recreate_if_invalid = "never"
  reusable            = false
  tags                = [local.truenas_talos_container.tailscale_tag]
}

resource "truenas_app" "talos_container" {
  app_name      = local.truenas_talos_container.app_name
  provider      = truenas.hosts[local.truenas_talos_container_host]
  remove_images = false

  custom_compose = yamlencode({
    services = {
      tailscale = {
        cap_add      = ["NET_ADMIN", "NET_RAW"]
        devices      = ["/dev/net/tun:/dev/net/tun"]
        image        = "tailscale/tailscale:v1.104.1"
        network_mode = "service:talos"
        restart      = "unless-stopped"
        environment = {
          TS_AUTHKEY    = tailscale_tailnet_key.container.key
          TS_AUTH_ONCE  = "true"
          TS_EXTRA_ARGS = "--accept-dns=false"
          TS_HOSTNAME   = "${local.truenas_talos_container.cluster}-${local.truenas_talos_container.app_name}"
          TS_ROUTES     = join(",", local.truenas_talos_container.tailscale_routes)
          TS_STATE_DIR  = "/var/lib/tailscale"
          TS_USERSPACE  = "false"
        }
        volumes = [{
          source = "${local.truenas_talos_container_storage_path}/tailscale"
          target = "/var/lib/tailscale"
          type   = "bind"
          bind = {
            create_host_path = true
          }
        }]
        depends_on = ["talos"]
      }
      talos = {
        cgroup = "private"
        # Keep private service DNS on its public Tailscale records rather than UniFi LAN overrides.
        dns        = ["1.1.1.1", "1.0.0.1"]
        hostname   = local.truenas_talos_container.name
        image      = "ghcr.io/siderolabs/talos:${local.clusters[local.truenas_talos_container.cluster].talos_version}"
        mem_limit  = "${local.truenas_talos_container.memory_gib}g"
        privileged = true
        read_only  = true
        restart    = "unless-stopped"
        environment = {
          PLATFORM = "container"
        }
        networks = {
          local = {}
          services = {
            ipv4_address = local.truenas_talos_container.address
            mac_address  = local.truenas_talos_container.mac
          }
        }
        security_opt = ["seccomp=unconfined"]
        tmpfs        = ["/run", "/system", "/tmp"]
        volumes = concat(
          # Mount parent paths before dataset-specific read-only mounts.
          [
            for host_path in try(local.truenas_talos_container.host_paths, []) : {
              read_only = try(host_path.read_only, false)
              source    = host_path.source
              target    = host_path.target
              type      = "bind"
              bind = {
                propagation = "rshared"
              }
            }
          ],
          [
            for volume in [
              { directory = "controlplane/opt", target = "/opt" },
              { directory = "controlplane/state", target = "/system/state" },
              { directory = "controlplane/var", target = "/var" },
              ] : {
              source = "${local.truenas_talos_container_storage_path}/${volume.directory}"
              target = volume.target
              type   = "bind"
              bind = {
                create_host_path = true
                propagation      = "rshared"
              }
            }
          ],
          [
            for dataset in local.truenas_talos_container.datasets : {
              source    = truenas_dataset.root["${local.truenas_talos_container_host}/${dataset.name}"].mount_point
              target    = "/var/mnt/datasets/${truenas_dataset.root["${local.truenas_talos_container_host}/${dataset.name}"].id}"
              type      = "bind"
              read_only = try(dataset.read_only, false)
              bind = {
                propagation = "rshared"
              }
            }
          ],
          [{
            read_only = true
            source    = "/lib/modules"
            target    = "/lib/modules"
            type      = "bind"
          }],
        )
      }
    }
    networks = {
      # macvlan cannot reach the host; this bridge gives Tailscale a local peer path.
      local = {
        driver   = "bridge"
        internal = true
      }
      services = {
        driver = "macvlan"
        driver_opts = {
          parent = local.truenas_hosts_services[local.truenas_talos_container_host].interface.bridge
        }
        ipam = {
          config = [{
            gateway = cidrhost(local.unifi_networks[local.truenas_talos_container_network_key].subnet, 1)
            subnet  = cidrsubnet(local.unifi_networks[local.truenas_talos_container_network_key].subnet, 0, 0)
          }]
        }
      }
    }
  })

}

resource "unifi_client" "talos_container" {
  allow_existing   = true
  fixed_ip         = local.truenas_talos_container.address
  local_dns_record = "${local.truenas_talos_container.app_name}.${local.machines[local.truenas_talos_container_host].network}.${local.domains.infrastructure}"
  mac              = local.truenas_talos_container.mac
  name             = local.truenas_talos_container.app_name
  network_id       = data.unifi_network.configured[local.truenas_talos_container_network_key].id
  note             = "Talos Kubernetes Node"
}
