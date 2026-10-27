data "talos_client_configuration" "cluster" {
  for_each = local.clusters

  client_configuration = talos_machine_secrets.cluster[each.key].client_configuration
  cluster_name         = each.key

  endpoints = flatten([
    for node_name, node in each.value.nodes : local.talos_client_endpoints[node_name]
    if node.machine_type == "controlplane"
  ])

  nodes = flatten([
    for node_name, node in each.value.nodes : local.talos_client_endpoints[node_name]
  ])
}

data "talos_image_factory_urls" "cluster" {
  for_each = local.clusters

  architecture      = each.value.image.architecture
  disk_image_format = each.value.image.platform == "oracle" ? "qcow2" : null
  platform          = each.value.image.platform
  schematic_id      = talos_image_factory_schematic.cluster[each.key].id
  talos_version     = each.value.talos_version
}

data "talos_machine_configuration" "container" {
  for_each = local.talos_containers

  cluster_endpoint   = local.talos_cluster_endpoints[each.value.cluster]
  cluster_name       = each.value.cluster
  kubernetes_version = local.clusters[each.value.cluster].kubernetes_version
  machine_secrets    = talos_machine_secrets.cluster[each.value.cluster].machine_secrets
  machine_type       = each.value.machine_type
  talos_version      = local.clusters[each.value.cluster].talos_version

  config_patches = concat(
    [yamlencode(local.talos_user_volume_local_path.directory)],
    each.value.machine_type == "controlplane" ? [
      yamlencode(local.talos_cluster_authentication_configuration),
      # Collect pods left Failed by graceful node shutdowns instead of waiting for 12,500.
      yamlencode({ apiVersion = "v1alpha1", kind = "KubeControllerManagerConfig", extraArgs = { "terminated-pod-gc-threshold" = "20" } }),
    ] : [],
    can(local.truenas_talos_containers[each.key]) || length(each.value.paths) > 0 ? [
      # v1.14's standalone KubeletConfig does not expose extraMounts.
      yamlencode({ apiVersion = "v1alpha1", kind = "KubeletConfig", "$patch" = "delete" }),
      yamlencode({
        machine = {
          kubelet = merge({
            image = "ghcr.io/siderolabs/kubelet:${local.clusters[each.value.cluster].kubernetes_version}"
            extraMounts = [{
              destination = "/var/mnt/datasets"
              options     = ["rbind", "rslave", "rw"]
              source      = "/var/mnt/datasets"
              type        = "bind"
            }]
            }, can(local.truenas_talos_containers[each.key]) ? {
            extraConfig = {
              # The stock kubelet image cannot report capacity for the host ZFS dataset.
              localStorageCapacityIsolation = false
              kubeReserved = {
                memory = "1Gi"
              }
              systemReserved = {
                memory = "${floor(data.truenas_system_info.container_host[each.key].physical_memory / 1024) - each.value.memory_gib * 1024 * 1024}Ki"
              }
            }
          } : {})
        }
      }),
    ] : [],
    [for document in local.talos_machine_configuration_documents_common[each.key] : yamlencode(document)],
  )
}

data "talos_machine_configuration" "node" {
  for_each = local.talos_nodes_installed

  cluster_endpoint   = local.talos_cluster_endpoints[each.value.cluster]
  cluster_name       = each.value.cluster
  kubernetes_version = local.clusters[each.value.cluster].kubernetes_version
  machine_secrets    = talos_machine_secrets.cluster[each.value.cluster].machine_secrets
  machine_type       = each.value.machine_type
  talos_version      = local.clusters[each.value.cluster].talos_version

  config_patches = [
    for document in local.talos_machine_configuration_documents[each.key] : yamlencode(document)
  ]
}

locals {
  talos_client_endpoints = {
    for name, node in local.talos_nodes : name => compact([
      try(node.tailscale_address, null),
      can(node.tailscale_address) ? null : try(local.tailscale_device_addresses[local.tailscale_machine_device_names[name]].ipv4, null),
      node.address,
    ])
  }

  talos_cluster_api_addresses = {
    for name, cluster in local.clusters :
    name => try(local.talos_nodes[cluster.api_node].tailscale_address, local.talos_nodes[cluster.api_node].address)
  }

  # The client ID and identity prefix match Headlamp's Pocket ID client and RBAC in kubelab.
  talos_cluster_authentication_configuration = {
    apiVersion = "v1alpha1"
    kind       = "KubeAuthenticationConfig"
    configuration = {
      anonymous = {
        enabled = true
        conditions = [
          { path = "/livez" },
          { path = "/readyz" },
          { path = "/healthz" },
        ]
      }
      jwt = [{
        claimMappings = {
          groups = {
            claim  = "groups"
            prefix = "pocket-id:"
          }
          username = {
            claim  = "sub"
            prefix = "pocket-id:"
          }
        }
        issuer = {
          audiences = [local.access.kubernetes.oidc_client_id]
          url       = local.access.oidc_issuer_url
        }
      }]
    }
  }

  talos_cluster_endpoints = {
    for name, cluster in local.clusters : name => try(
      cluster.endpoint,
      "https://${local.talos_cluster_api_addresses[name]}:6443",
    )
  }

  # Public DNS keeps private service names on their Tailscale records rather than
  # UniFi LAN overrides.
  talos_container_dns_servers = ["1.1.1.1", "1.0.0.1"]

  # Privileged, so GPU pods see the host's /dev/dri and /dev/kfd. Podman's systemd
  # mode would replace Talos's own /run handling, so it stays off. Host directories
  # sit beside TrueNAS nodes' datasets, so pods share one hostPath root.
  talos_container_files = {
    for name, container in local.talos_container_hosts : name => {
      "/etc/containers/systemd/talos-local.network" = {
        content = <<-EOT
          # macvlan cannot reach the host; this bridge gives Tailscale a peer path.
          [Network]
          Internal=true
          NetworkName=talos-local
        EOT
        mode    = "0644"
      }
      "/etc/containers/systemd/talos-services.network" = {
        content = <<-EOT
          [Network]
          Driver=macvlan
          Gateway=${cidrhost(local.unifi_networks[container.network_key].subnet, 1)}
          NetworkName=talos-services
          Options=parent=${container.interface}
          Subnet=${cidrsubnet(local.unifi_networks[container.network_key].subnet, 0, 0)}
        EOT
        mode    = "0644"
      }
      "/etc/containers/systemd/talos-tailscale.container" = {
        content = <<-EOT
          [Unit]
          Description=Talos Tailscale
          PartOf=talos.service

          [Container]
          AddCapability=CAP_NET_ADMIN CAP_NET_RAW
          AddDevice=/dev/net/tun
          ContainerName=talos-tailscale
          EnvironmentFile=/etc/talos/tailscale.env
          Image=${local.images.tailscale}
          Network=talos.container
          Volume=talos-tailscale:${local.talos_container_tailscale_state_directory}

          [Service]
          Restart=always

          [Install]
          WantedBy=talos.service
        EOT
        mode    = "0644"
      }
      "/etc/containers/systemd/talos.container" = {
        content = <<-EOT
          [Unit]
          Description=Talos Kubernetes Node

          [Container]
          ContainerName=talos
          ${join("\n", [for server in local.talos_container_dns_servers : "DNS=${server}"])}
          Environment=PLATFORM=container
          HostName=${container.name}
          Image=${container.image}
          ${join("\n", [for path in container.paths : "Mount=type=bind,source=${path},target=/var/mnt/datasets/${basename(path)},bind-propagation=rslave"])}
          Network=talos-local.network
          Network=talos-services.network:ip=${container.address},mac=${container.mac}
          PodmanArgs=--cgroupns=private --privileged --systemd=false
          ReadOnly=true
          ReadOnlyTmpfs=false
          SeccompProfile=unconfined
          SecurityLabelDisable=true
          Tmpfs=/run
          Tmpfs=/system
          Tmpfs=/tmp
          Volume=/lib/modules:/lib/modules:ro
          Volume=talos-opt:/opt
          Volume=talos-state:/system/state
          Volume=talos-var:/var

          [Service]
          Restart=always
          TimeoutStartSec=900

          [Install]
          WantedBy=multi-user.target
        EOT
        mode    = "0644"
      }
      "/etc/talos/tailscale.env" = {
        content = join("", [for key, value in local.talos_container_tailscale_environment[name] : "${key}=${value}\n"])
        mode    = "0600"
      }
    }
  }

  talos_container_hosts = {
    for name, container in local.talos_containers : name => merge(container, {
      interface = one([
        for interface in local.machines[name].interfaces : interface.name
        if cidrcontains(local.unifi_networks[container.network_key].subnet, interface.address)
      ])
    })
    if can(local.sync_hosts[name])
  }

  # Shared by the TrueNAS and Podman sidecars.
  talos_container_tailscale_environment = {
    for name, container in local.talos_containers : name => {
      TS_AUTH_ONCE  = "true"
      TS_AUTHKEY    = tailscale_tailnet_key.talos_container[name].key
      TS_EXTRA_ARGS = "--accept-dns=false"
      TS_HOSTNAME   = container.device_name
      TS_ROUTES     = join(",", container.tailscale_routes)
      TS_STATE_DIR  = local.talos_container_tailscale_state_directory
      TS_USERSPACE  = "false"
    }
  }

  talos_container_tailscale_state_directory = "/var/lib/tailscale"

  talos_containers = {
    for name, node in local.talos_nodes : name => merge(node, node.container, {
      device_name = "${node.cluster}-${local.machine_hostnames[name]}-talos"
      image       = "ghcr.io/siderolabs/talos:${local.clusters[node.cluster].talos_version}"
      name        = local.machine_hostnames[name]
      network_key = one([
        for key, network in local.unifi_networks : key
        if startswith(key, "${local.machines[name].network}/") && cidrcontains(network.subnet, node.address)
      ])
      paths = try(node.container.paths, [])
    })
    if node.configuration_delivery == "container"
  }

  talos_machine_bootstrap_nodes = {
    for name, node in local.talos_nodes : name => node
    if node.machine_type == "controlplane" && try(node.bootstrap, false)
  }

  talos_machine_configuration_documents = {
    for name, node in local.talos_nodes : name => concat([
      {
        machine = merge(
          length(node.sysctls) > 0 ? { sysctls = node.sysctls } : {},
          length(node.time_servers) > 0 ? { time = { servers = node.time_servers } } : {},
        )
      },
      ], local.talos_machine_configuration_documents_common[name], [
      {
        apiVersion = "v1alpha1"
        kind       = "ExtensionServiceConfig"
        name       = "tailscale"
        environment = compact([
          "TS_AUTHKEY=${tailscale_tailnet_key.server[name].key}",
          "TS_HOSTNAME=${local.machine_tailscale_names[name]}",
          "TS_EXTRA_ARGS=--accept-routes=true --reset",
          length(node.tailscale_routes) > 0 ? "TS_ROUTES=${join(",", node.tailscale_routes)}" : null,
        ])
      },
      local.talos_user_volume_local_path[can(local.machines[name].oci.volumes.data) ? "partition" : "directory"],
      ], node.machine_type == "controlplane" ? [local.talos_cluster_authentication_configuration] : [], node.install_disk != null ? [{
        apiVersion = "v1alpha1"
        kind       = "UnattendedInstallConfig"
        installer = {
          image = data.talos_image_factory_urls.cluster[node.cluster].urls.installer
        }
        provisioning = {
          diskSelector = {
            match = "disk.dev_path == ${jsonencode(node.install_disk)}"
          }
        }
    }] : [])
  }

  talos_machine_configuration_documents_common = {
    for name, node in local.talos_nodes : name => [
      {
        apiVersion = "v1alpha1"
        kind       = "KubeFlannelCNIConfig"
        "$patch"   = "delete"
      },
      {
        apiVersion     = "v1alpha1"
        kind           = "KubeNetworkConfig"
        podSubnets     = [local.clusters[node.cluster].pod_subnet]
        serviceSubnets = [local.clusters[node.cluster].service_subnet]
      },
      {
        apiVersion = "v1alpha1"
        kind       = "KubeNodeConfig"
        labels = merge(
          { "node.${local.domains.services}/network" = name == try(local.clusters[node.cluster].public_node, null) ? "external" : "internal" },
          node.dedicated != null ? { "node.${local.domains.services}/dedicated" = node.dedicated } : {},
        )
        nodeIP = {
          validSubnets = [try("${node.tailscale_address}/32", local.tailscale_address_ranges.ipv4)]
        }
        taints = node.dedicated != null ? { "node.${local.domains.services}/dedicated" = "${node.dedicated}:NoSchedule" } : { "$patch" = "delete" }
      },
      {
        apiVersion = "v1alpha1"
        kind       = "ResolverConfig"
        hostDNS = merge({
          enabled              = true
          forwardKubeDNSToHost = true
        }, node.configuration_delivery == "container" ? {} : { resolveMemberNames = true })
      },
      {
        apiVersion = "v1alpha1"
        kind       = "HostnameConfig"
        auto       = "off"
        hostname   = local.machine_hostnames[name]
      },
    ]
  }

  talos_nodes = merge([
    for cluster_name, cluster in local.clusters : {
      for node_name, node in cluster.nodes : node_name => merge(node, {
        address                = try(node.address, local.machine_private_ipv4_addresses[node_name])
        cluster                = cluster_name
        configuration_delivery = try(node.configuration_delivery, null)
        dedicated              = try(node.dedicated, null)
        install_disk           = try(node.install_disk, null)
        sysctls                = try(node.sysctls, {})
        tailscale_routes       = try(node.tailscale_routes, [])
        tailscale_tag          = try(node.configuration_delivery, null) == "container" ? "tag:cluster-${cluster_name}" : "tag:${local.machines[node_name].type}"
        time_servers           = try(node.time_servers, [])
      })
    }
  ]...)

  talos_nodes_installed = {
    for name, node in local.talos_nodes : name => node
    if node.configuration_delivery != "container"
  }

  # Keyed by volume type so each node selects one shape without type coercion.
  talos_user_volume_local_path = {
    directory = {
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = "local-path-provisioner"
      volumeType = "directory"
    }
    partition = {
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = "local-path-provisioner"
      volumeType = "partition"
      provisioning = {
        grow    = true
        minSize = "1GiB"
        diskSelector = {
          match = "!system_disk"
        }
      }
    }
  }
}

resource "talos_cluster_kubeconfig" "cluster" {
  for_each = local.clusters

  client_configuration = talos_machine_secrets.cluster[each.key].client_configuration
  endpoint             = local.talos_cluster_api_addresses[each.key]
  node                 = local.talos_cluster_api_addresses[each.key]

  timeouts = {
    create = "10m"
    update = "10m"
  }

  depends_on = [talos_machine_bootstrap.control_plane]
}

resource "talos_image_factory_schematic" "cluster" {
  for_each = local.clusters

  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = each.value.image.extensions
      }
    }
  })
}

resource "talos_machine_bootstrap" "control_plane" {
  for_each = local.talos_machine_bootstrap_nodes

  client_configuration_wo = talos_machine_secrets.cluster[each.value.cluster].client_configuration
  endpoint                = each.value.address
  node                    = each.value.address

  timeouts = {
    create = "10m"
  }

  lifecycle {
    precondition {
      condition     = try(each.value.configuration_delivery == "container" ? talos_machine_configuration_apply.container[each.key].id : talos_machine_configuration_apply.node[each.key].id, "") != ""
      error_message = "Deliver this node's Talos configuration before bootstrapping it."
    }
  }
}

resource "talos_machine_configuration_apply" "container" {
  for_each = local.talos_containers

  apply_mode                     = "no_reboot"
  client_configuration_wo        = talos_machine_secrets.cluster[each.value.cluster].client_configuration
  endpoint                       = each.value.address
  machine_configuration_input_wo = data.talos_machine_configuration.container[each.key].machine_configuration
  node                           = each.value.address

  on_destroy = {
    graceful = false
    reboot   = false
    reset    = false
  }

  depends_on = [truenas_app.talos_container]

  lifecycle {
    precondition {
      condition     = onepassword_item.talos_recovery[each.value.cluster].uuid != ""
      error_message = "Store this cluster's Talos recovery material before applying container configuration."
    }
  }
}

resource "talos_machine_configuration_apply" "node" {
  for_each = local.talos_nodes_installed

  apply_mode                     = "no_reboot"
  client_configuration_wo        = talos_machine_secrets.cluster[each.value.cluster].client_configuration
  endpoint                       = local.talos_client_endpoints[each.key][0]
  machine_configuration_input_wo = data.talos_machine_configuration.node[each.key].machine_configuration
  node                           = each.value.address

  on_destroy = {
    graceful = false
    reboot   = false
    reset    = false
  }

  timeouts = {
    create = "10m"
    update = "10m"
  }

  depends_on = [oci_core_instance.node]

  lifecycle {
    precondition {
      condition     = onepassword_item.talos_recovery[each.value.cluster].uuid != ""
      error_message = "Store this cluster's Talos recovery material before applying node configuration."
    }
  }
}

resource "talos_machine_secrets" "cluster" {
  for_each = local.clusters

  talos_version = each.value.talos_version

  lifecycle {
    # The provider regenerates every cluster secret when this changes; it only
    # sets generation defaults, so upgrades must leave the secrets alone.
    ignore_changes  = [talos_version]
    prevent_destroy = true
  }
}
