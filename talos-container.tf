data "talos_machine_configuration" "container_test" {
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
              memory = "${local.truenas_talos_container_test.host_memory_kib - local.truenas_talos_container_test.memory_gib * 1024 * 1024}Ki"
            }
          }
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = local.truenas_talos_container_test.name
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
        validSubnets = ["100.120.55.119/32"]
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
  truenas_talos_container_test = {
    address = "10.4.0.7"
    # Match Kimbap's MemTotal; reserve memory outside the container's budget.
    host_memory_kib = 65253188
    mac             = "02:74:61:63:6f:01"
    memory_gib      = 32
    name            = "kimbap"
  }
}

resource "talos_machine_configuration_apply" "container_test" {
  apply_mode                     = "no_reboot"
  endpoint                       = local.truenas_talos_container_test.address
  machine_configuration_input_wo = data.talos_machine_configuration.container_test.machine_configuration
  node                           = local.truenas_talos_container_test.address

  client_configuration_wo = {
    ca_certificate     = talos_machine_secrets.cluster["syd"].client_configuration.ca_certificate
    client_certificate = talos_machine_secrets.cluster["syd"].client_configuration.client_certificate
    client_key         = talos_machine_secrets.cluster["syd"].client_configuration.client_key
  }

  on_destroy = {
    graceful = false
    reboot   = false
    reset    = false
  }

  depends_on = [truenas_app.talos_container_test]
}

resource "tailscale_tailnet_key" "container_test" {
  description         = "Talos container test bootstrap"
  expiry              = local.access.tailscale.key_expiry_seconds
  preauthorized       = true
  recreate_if_invalid = "never"
  reusable            = false
  tags                = ["tag:vm"]
}

resource "truenas_app" "talos_container_test" {
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
          TS_AUTHKEY    = tailscale_tailnet_key.container_test.key
          TS_AUTH_ONCE  = "true"
          TS_EXTRA_ARGS = "--accept-dns=false"
          TS_HOSTNAME   = "syd-kimbap"
          TS_ROUTES     = "10.4.0.0/22"
          TS_STATE_DIR  = "/var/lib/tailscale"
          TS_USERSPACE  = "false"
        }
        volumes = [{
          source = "/mnt/${truenas_dataset.talos_container_test.pool}/${truenas_dataset.talos_container_test.name}/tailscale"
          target = "/var/lib/tailscale"
          type   = "bind"
          bind = {
            create_host_path = true
          }
        }]
        depends_on = ["talos"]
      }
      talos = {
        cgroup      = "private"
        hostname    = local.truenas_talos_container_test.name
        image       = "ghcr.io/siderolabs/talos:${local.clusters["syd"].talos_version}"
        mac_address = local.truenas_talos_container_test.mac
        mem_limit   = "${local.truenas_talos_container_test.memory_gib}g"
        privileged  = true
        read_only   = true
        restart     = "unless-stopped"
        environment = {
          PLATFORM = "container"
        }
        networks = {
          services = {
            ipv4_address = local.truenas_talos_container_test.address
          }
        }
        security_opt = ["seccomp=unconfined"]
        tmpfs        = ["/run", "/system", "/tmp"]
        volumes = concat(
          [
            for volume in [
              { directory = "controlplane/opt", target = "/opt" },
              { directory = "controlplane/state", target = "/system/state" },
              { directory = "controlplane/var", target = "/var" },
              ] : {
              source = "/mnt/${truenas_dataset.talos_container_test.pool}/${truenas_dataset.talos_container_test.name}/${volume.directory}"
              target = volume.target
              type   = "bind"
              bind = {
                create_host_path = true
                propagation      = "rshared"
              }
            }
          ],
          [
            { source = "/mnt/truenas-nvme/bichon", target = "/var/mnt/datasets/truenas-nvme/bichon", type = "bind", read_only = false, bind = { propagation = "rshared" } },
            { source = "/mnt/truenas-nvme/bookorbit", target = "/var/mnt/datasets/truenas-nvme/bookorbit", type = "bind", read_only = false, bind = { propagation = "rshared" } },
            { source = "/mnt/truenas-nvme/clusters/mbk", target = "/var/mnt/datasets/truenas-nvme/clusters/mbk", type = "bind", read_only = false, bind = { propagation = "rshared" } },
            { source = "/mnt/truenas-nvme/immich", target = "/var/mnt/datasets/truenas-nvme/immich", type = "bind", read_only = false, bind = { propagation = "rshared" } },
            { source = "/mnt/truenas-nvme/papra", target = "/var/mnt/datasets/truenas-nvme/papra", type = "bind", read_only = false, bind = { propagation = "rshared" } },
            { source = "/mnt/truenas-nvme/romm", target = "/var/mnt/datasets/truenas-nvme/romm", type = "bind", read_only = false, bind = { propagation = "rshared" } },
            { source = "/mnt/truenas/clusters/mbk", target = "/var/mnt/datasets/truenas/clusters/mbk", type = "bind", read_only = false, bind = { propagation = "rshared" } },
            { source = "/mnt/truenas/games", target = "/var/mnt/datasets/truenas/games", type = "bind", read_only = false, bind = { propagation = "rshared" } },
            { source = "/mnt/truenas/icloud-photos", target = "/var/mnt/datasets/truenas/icloud-photos", type = "bind", read_only = true, bind = { propagation = "rshared" } },
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

  depends_on = [unifi_client.talos_container_test]
}

resource "truenas_dataset" "talos_container_test" {
  atime       = "OFF"
  compression = "LZ4"
  name        = "talos-test"
  pool        = local.storage.truenas["kimbap"].dataset_defaults.pool
  provider    = truenas.hosts["kimbap"]
}

resource "unifi_client" "talos_container_test" {
  fixed_ip   = "10.4.0.8"
  mac        = "02:74:61:6c:6f:01"
  name       = "talos-test"
  network_id = data.unifi_network.configured["mbk/services"].id
  note       = "Talos Container Test"
}
