data "talos_machine_configuration" "container" {
  cluster_endpoint   = local.talos_cluster_endpoints["syd"]
  cluster_name       = "syd"
  kubernetes_version = local.clusters["syd"].kubernetes_version
  machine_secrets    = talos_machine_secrets.cluster["syd"].machine_secrets
  machine_type       = "controlplane"
  talos_version      = local.clusters["syd"].talos_version

  config_patches = [
    yamlencode(local.talos_user_volume_local_path_directory),
    yamlencode(local.talos_cluster_authentication_configuration),
    # v1.14's standalone KubeletConfig does not expose extraMounts.
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeletConfig", "$patch" = "delete" }),
    yamlencode({
      machine = {
        kubelet = {
          image = "ghcr.io/siderolabs/kubelet:${local.clusters["syd"].kubernetes_version}"
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
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = local.truenas_talos_container.name
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeFlannelCNIConfig"
      "$patch"   = "delete"
    }),
    yamlencode({
      apiVersion     = "v1alpha1"
      kind           = "KubeNetworkConfig"
      podSubnets     = [local.clusters["syd"].pod_subnet]
      serviceSubnets = [local.clusters["syd"].service_subnet]
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeNodeConfig"
      nodeIP = {
        validSubnets = ["${local.talos_nodes["kimbap"].tailscale_address}/32"]
      }
      taints = {
        "$patch" = "delete"
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ResolverConfig"
      hostDNS = {
        enabled              = true
        forwardKubeDNSToHost = true
      }
    }),
  ]
}

locals {
  truenas_talos_container = {
    address         = local.talos_nodes["kimbap"].address
    host_memory_kib = local.talos_nodes["kimbap"].container.host_memory_kib
    mac             = local.talos_nodes["kimbap"].container.mac
    memory_gib      = local.talos_nodes["kimbap"].container.memory_gib
    name            = "kimbap"
  }
}

resource "talos_machine_configuration_apply" "container" {
  apply_mode                     = "no_reboot"
  client_configuration_wo        = talos_machine_secrets.cluster["syd"].client_configuration
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
  tags                = ["tag:vm"]
}

resource "truenas_app" "talos_container" {
  app_name      = "talos"
  provider      = truenas.hosts["kimbap"]
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
          TS_HOSTNAME   = "syd-talos"
          TS_ROUTES     = join(",", local.talos_nodes["kimbap"].tailscale_routes)
          TS_STATE_DIR  = "/var/lib/tailscale"
          TS_USERSPACE  = "false"
        }
        volumes = [{
          source = "/mnt/${truenas_dataset.root["kimbap/talos"].pool}/${truenas_dataset.root["kimbap/talos"].name}/tailscale"
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
        dns         = ["1.1.1.1", "1.0.0.1"]
        hostname    = local.truenas_talos_container.name
        image       = "ghcr.io/siderolabs/talos:${local.clusters["syd"].talos_version}"
        mac_address = local.truenas_talos_container.mac
        mem_limit   = "${local.truenas_talos_container.memory_gib}g"
        privileged  = true
        read_only   = true
        restart     = "unless-stopped"
        environment = {
          PLATFORM = "container"
        }
        networks = {
          local = {}
          services = {
            ipv4_address = local.truenas_talos_container.address
          }
        }
        security_opt = ["seccomp=unconfined"]
        tmpfs        = ["/run", "/system", "/tmp"]
        volumes = concat(
          # Mount parent paths before dataset-specific read-only mounts.
          [
            for host_path in try(local.talos_nodes["kimbap"].container.host_paths, []) : {
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
              source = "/mnt/${truenas_dataset.root["kimbap/talos"].pool}/${truenas_dataset.root["kimbap/talos"].name}/${volume.directory}"
              target = volume.target
              type   = "bind"
              bind = {
                create_host_path = true
                propagation      = "rshared"
              }
            }
          ],
          [
            for dataset in local.talos_nodes["kimbap"].container.datasets : {
              source    = truenas_dataset.root["kimbap/${dataset.name}"].mount_point
              target    = "/var/mnt/datasets/${truenas_dataset.root["kimbap/${dataset.name}"].id}"
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
          parent = local.truenas_hosts_services["kimbap"].interface.bridge
        }
        ipam = {
          config = [{
            gateway = cidrhost(local.networks["mbk"].subnets.services.cidr, 1)
            subnet  = cidrsubnet(local.networks["mbk"].subnets.services.cidr, 0, 0)
          }]
        }
      }
    }
  })

}

resource "unifi_client" "talos_container" {
  allow_existing   = true
  fixed_ip         = local.truenas_talos_container.address
  local_dns_record = "talos.mbk.excloo.net"
  mac              = local.truenas_talos_container.mac
  name             = "talos"
  network_id       = data.unifi_network.configured["mbk/services"].id
  note             = "Talos Kubernetes Node"
}
