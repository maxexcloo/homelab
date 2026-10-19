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
  cluster_endpoint   = local.talos_cluster_endpoints[local.truenas_talos_container.cluster]
  cluster_name       = local.truenas_talos_container.cluster
  kubernetes_version = local.clusters[local.truenas_talos_container.cluster].kubernetes_version
  machine_secrets    = talos_machine_secrets.cluster[local.truenas_talos_container.cluster].machine_secrets
  machine_type       = local.truenas_talos_container.machine_type
  talos_version      = local.clusters[local.truenas_talos_container.cluster].talos_version

  config_patches = concat(
    [yamlencode(local.talos_user_volume_local_path.directory)],
    local.truenas_talos_container.machine_type == "controlplane" ? [
      yamlencode(local.talos_cluster_authentication_configuration),
      # Collect pods left Failed by graceful node shutdowns instead of waiting for 12,500.
      yamlencode({ apiVersion = "v1alpha1", kind = "KubeControllerManagerConfig", extraArgs = { "terminated-pod-gc-threshold" = "20" } }),
    ] : [],
    [
      # v1.14's standalone KubeletConfig does not expose extraMounts.
      yamlencode({ apiVersion = "v1alpha1", kind = "KubeletConfig", "$patch" = "delete" }),
      yamlencode({
        machine = {
          kubelet = {
            image = "ghcr.io/siderolabs/kubelet:${local.clusters[local.truenas_talos_container.cluster].kubernetes_version}"
            extraConfig = {
              # The stock kubelet image cannot report capacity for the host ZFS dataset.
              localStorageCapacityIsolation = false
              kubeReserved = {
                memory = "1Gi"
              }
              systemReserved = {
                memory = "${floor(data.truenas_system_info.container_host.physical_memory / 1024) - local.truenas_talos_container.memory_gib * 1024 * 1024}Ki"
              }
            }
            extraMounts = [{
              destination = "/var/mnt/datasets"
              options     = ["rbind", "rshared", "rw"]
              source      = "/var/mnt/datasets"
              type        = "bind"
            }]
          }
        }
      }),
    ],
    [for document in local.talos_machine_configuration_documents_common[local.truenas_talos_container_host] : yamlencode(document)],
  )
}

data "talos_machine_configuration" "node" {
  for_each = { for name, node in local.talos_nodes : name => node if node.configuration_delivery != "container" }

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
          url       = local.access.kubernetes.oidc_issuer_url
        }
      }]
    }
  }

  talos_client_endpoints = {
    for name, node in local.talos_nodes : name => compact([
      try(node.tailscale_address, null),
      node.address,
      can(node.tailscale_address) ? null : try(local.tailscale_device_addresses[local.tailscale_machine_device_names[name]].ipv4, null),
    ])
  }

  talos_cluster_endpoints = {
    for name, cluster in local.clusters : name => try(
      cluster.endpoint,
      "https://${try(local.talos_nodes[cluster.api_node].tailscale_address, local.talos_nodes[cluster.api_node].address)}:6443",
    )
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
          "TS_EXTRA_ARGS=--accept-routes=true",
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
        labels = {
          "node.${local.domains.services}/network" = name == try(local.clusters[node.cluster].public_node, null) ? "external" : "internal"
        }
        nodeIP = {
          validSubnets = node.configuration_delivery == "container" ? ["${node.tailscale_address}/32"] : [local.tailscale_address_ranges.ipv4]
        }
        taints = {
          "$patch" = "delete"
        }
      },
      {
        apiVersion = "v1alpha1"
        kind       = "ResolverConfig"
        hostDNS = merge({
          enabled              = true
          forwardKubeDNSToHost = true
        }, node.configuration_delivery == "container" ? {} : { resolveMemberNames = true })
        # Pods inherit node search domains; provider DHCP domains such as OCI's
        # private zone fail on nodes whose resolvers cannot answer them.
        searchDomains = {
          domains = []
        }
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
        install_disk           = try(node.install_disk, null)
        sysctls                = try(node.sysctls, {})
        tailscale_routes       = try(node.tailscale_routes, [])
        time_servers           = try(node.time_servers, [])
      })
    }
  ]...)

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
  endpoint             = try(local.talos_nodes[each.value.api_node].tailscale_address, local.talos_nodes[each.value.api_node].address)
  node                 = try(local.talos_nodes[each.value.api_node].tailscale_address, local.talos_nodes[each.value.api_node].address)

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
      condition     = try(each.value.configuration_delivery == "container" ? talos_machine_configuration_apply.container.id : talos_machine_configuration_apply.node[each.key].id, "") != ""
      error_message = "Deliver this node's Talos configuration before bootstrapping it."
    }
  }
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

  lifecycle {
    precondition {
      condition     = onepassword_item.talos_recovery[local.truenas_talos_container.cluster].uuid != ""
      error_message = "Store this cluster's Talos recovery material before applying container configuration."
    }
  }
}

resource "talos_machine_configuration_apply" "node" {
  for_each = { for name, node in local.talos_nodes : name => node if node.configuration_delivery != "container" }

  apply_mode                     = "no_reboot"
  client_configuration_wo        = talos_machine_secrets.cluster[each.value.cluster].client_configuration
  endpoint                       = each.value.configuration_delivery == "metadata" ? oci_core_instance.node[each.key].private_ip : each.value.address
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
    prevent_destroy = true
  }
}

resource "terraform_data" "talos_configuration_validation" {
  lifecycle {
    precondition {
      condition = alltrue([
        for cluster in values(local.clusters) : try(cluster.nodes[cluster.api_node].machine_type == "controlplane", false)
      ])
      error_message = "Every cluster API node must be a control plane in that cluster."
    }

    precondition {
      condition = alltrue(flatten([
        for cluster in values(local.clusters) : [
          for node_name, node in cluster.nodes : (
            contains(["api", "container", "metadata"], try(node.configuration_delivery, "")) &&
            (try(node.configuration_delivery, "") != "metadata" || try(local.machines[node_name].provider, null) == "oci")
          )
        ]
      ]))
      error_message = "Every cluster node must use API, container or OCI metadata configuration delivery."
    }

    precondition {
      condition = alltrue([
        for cluster in values(local.clusters) : length([
          for node in values(cluster.nodes) : node
          if node.machine_type == "controlplane" && try(node.bootstrap, false)
        ]) == 1
      ])
      error_message = "Every enabled Talos cluster must have exactly one bootstrap control plane."
    }

    precondition {
      condition = length(flatten([
        for cluster in values(local.clusters) : keys(cluster.nodes)
      ])) == length(local.machine_clusters)
      error_message = "A machine may belong to only one cluster."
    }
  }
}
