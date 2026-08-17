locals {
  access      = yamldecode(file("${path.module}/data/access.yaml"))
  clusters    = yamldecode(file("${path.module}/data/clusters.yaml")).clusters
  deployments = yamldecode(file("${path.module}/data/deployments.yaml")).deployments
  domains     = yamldecode(file("${path.module}/data/domains.yaml"))
  machines    = yamldecode(file("${path.module}/data/machines.yaml")).machines
  networks    = yamldecode(file("${path.module}/data/networks.yaml")).networks
  storage     = yamldecode(file("${path.module}/data/storage.yaml"))

  talos_clusters = {
    for name, cluster in local.clusters : name => cluster
    if cluster.talos_enabled
  }

  machine_fqdns = {
    for name, machine in local.machines :
    name => "${name}.${machine.location}.${local.domains.domains.infrastructure}"
  }
  cluster_api_fqdns = {
    for name in keys(local.clusters) :
    name => "api.${name}.${local.domains.domains.services}"
  }

  truenas_deployments = {
    for name, deployment in local.deployments : name => deployment
    if deployment.provider == "truenas"
  }
  home_network         = local.networks[local.truenas_host_machine.location]
  truenas_host         = one(distinct([for deployment in values(local.truenas_deployments) : deployment.host]))
  truenas_host_machine = local.machines[local.truenas_host]
  truenas_service_nic  = local.home_network.interfaces.services
  virtual_machines     = local.truenas_deployments
  truenas_datasets = merge([
    for target, storage in local.storage.targets : {
      for name, dataset in storage.datasets : "${target}/${name}" => merge(dataset, {
        name   = name
        target = target
      })
    }
  ]...)
  truenas_nfs_shares = merge([
    for target, storage in local.storage.targets : {
      for name, share in storage.nfs_shares : "${target}/${name}" => merge(share, {
        dataset_key = "${target}/${share.dataset}"
        name        = name
        networks = [
          for network in share.networks : cidrsubnet(
            local.networks[network.location].unifi.networks[network.network].subnet,
            0,
            0,
          )
        ]
        target = target
      })
    }
  ]...)
  truenas_snapshot_tasks = merge([
    for target, storage in local.storage.targets : {
      for name, task in storage.snapshot_tasks : "${target}/${name}" => merge(task, {
        name   = name
        target = target
      })
    }
  ]...)
  truenas_storage_targets = local.storage.targets

  oci_networks = {
    for name, network in local.networks : name => network.oci
    if try(network.oci, null) != null
  }
  oci_deployments = {
    for name, deployment in local.deployments : name => merge(deployment, {
      cluster = local.machines[name].cluster
    })
    if deployment.provider == "oci"
  }
  oci_nodes = {
    for name, deployment in local.oci_deployments : name => deployment
    if local.clusters[deployment.cluster].talos_enabled
  }
  oci_node_egress_rules = merge([
    for name, node in local.oci_nodes : {
      for family, destination in merge(
        { ipv4 = "0.0.0.0/0" },
        local.oci_networks[node.network].ipv6_enabled ? { ipv6 = "::/0" } : {},
        ) : "${name}/${family}" => {
        destination = destination
        node        = name
      }
    }
  ]...)
  oci_cluster_name = one(values(local.oci_deployments)).cluster
  oci_talos_images = {
    for name, cluster in local.clusters : name => cluster
    if cluster.talos_enabled && cluster.image.platform == "oracle"
  }

  cloudflare_account_name = local.domains.cloudflare.account_name
  cloudflare_acme_consumers = {
    for name, consumer in local.domains.cloudflare.acme_consumers : name => merge(consumer, {
      challenge_hostname = try(consumer.machine, null) != null ? local.machine_fqdns[consumer.machine] : "${consumer.cluster}.${local.domains.domains.services}"
      credential_scope   = try(consumer.machine, null) != null ? local.machine_fqdns[consumer.machine] : name
      target_hostname    = "${name}.${local.domains.domains.acme}"
      title              = try(consumer.machine, null) != null ? "Cloudflare ACME DNS: ${local.machine_fqdns[consumer.machine]}" : "cloudflare-acme-${name}"
      vault              = try(consumer.machine, null) != null ? "homelab" : "kubernetes/${name}"
    })
  }
  cloudflare_tunnels = {
    for name, consumer in local.domains.cloudflare.tunnel_consumers : name => merge(consumer, {
      credential_scope = try(consumer.machine, null) != null ? local.machine_fqdns[consumer.machine] : name
      tags             = try(consumer.machine, null) != null ? toset(["Homelab", "Cloudflare", "Tunnel"]) : toset(["Homelab", "Cloudflare", "Kubernetes"])
      title            = try(consumer.machine, null) != null ? "Cloudflare Tunnel: ${local.machine_fqdns[consumer.machine]}" : "cloudflare-tunnel-${name}"
      vault            = try(consumer.machine, null) != null ? "homelab" : "kubernetes/${name}"
    })
  }
  cloudflare_zones = toset(concat(
    values(local.domains.domains),
    [for source_file in local.dns_source_files : source_file.zone.name],
  ))
  dns_derived_records = merge(
    {
      for name, machine in local.machines : "machine/${name}/a" => {
        comment  = "Managed by OpenTofu"
        content  = try(machine.public_ipv4, machine.address)
        name     = local.machine_fqdns[name]
        priority = null
        proxied  = false
        ttl      = 300
        type     = "A"
        zone     = local.domains.domains.infrastructure
      }
      if try(machine.public_ipv4, null) != null || try(machine.address, null) != null
    },
    {
      for name, machine in local.machines : "machine/${name}/aaaa" => {
        comment  = "Managed by OpenTofu"
        content  = machine.public_ipv6
        name     = local.machine_fqdns[name]
        priority = null
        proxied  = false
        ttl      = 300
        type     = "AAAA"
        zone     = local.domains.domains.infrastructure
      }
      if try(machine.public_ipv6, null) != null
    },
    {
      for cluster_name, cluster in local.clusters : "cluster/${cluster_name}/api" => {
        comment  = "Managed by OpenTofu"
        content  = local.machines[cluster.api_node].address
        name     = local.cluster_api_fqdns[cluster_name]
        priority = null
        proxied  = false
        ttl      = 300
        type     = "A"
        zone     = local.domains.domains.services
      }
    },
    {
      for name, consumer in local.cloudflare_acme_consumers : "acme/${name}" => {
        comment  = "Managed by OpenTofu"
        content  = consumer.target_hostname
        name     = "_acme-challenge.${consumer.challenge_hostname}"
        priority = null
        proxied  = false
        ttl      = 300
        type     = "CNAME"
        zone = one([
          for zone in values(local.domains.domains) : zone
          if consumer.challenge_hostname == zone || endswith(consumer.challenge_hostname, ".${zone}")
        ])
      }
    },
  )

  onepassword_vaults = merge(
    local.access.onepassword.vaults,
    {
      for name in keys(local.clusters) : "kubernetes/${name}" => "Kubernetes: ${name}"
    },
  )
  tailscale_admin_identities = local.access.tailscale.admin_identities
  tailscale_key_expiry       = local.access.tailscale.key_expiry_seconds
  tailscale_host_tags = toset(concat(
    [for machine in values(local.machines) : "tag:${machine.tailscale_tag}"],
    [for tag in local.access.tailscale.additional_tags : "tag:${tag}"],
  ))
  tailscale_operator_tags = {
    for name in keys(local.clusters) : name => "${name}-operator"
  }
  tailscale_routes = toset(flatten([
    for cluster in values(local.clusters) : flatten([
      for node in values(cluster.nodes) : try(node.tailscale_routes, [])
    ])
  ]))

  talos_nodes = merge([
    for cluster_name, cluster in local.talos_clusters : {
      for node_name, node in cluster.nodes : node_name => merge(node, {
        address = local.machines[node_name].address
        cluster = cluster_name
      })
    }
  ]...)
  talos_schematic_ids = {
    for name, schematic in talos_image_factory_schematic.cluster :
    name => schematic.id
  }
  cluster_endpoints = {
    for name, cluster in local.clusters : name => try(
      cluster.endpoint,
      "https://${local.machines[cluster.api_node].address}:6443",
    )
  }
  talos_connection_endpoints = {
    for name, node in local.talos_nodes :
    name => lookup(var.talos_connection_endpoints, name, node.address)
  }
  talos_bootstrap_nodes = {
    for name, node in local.talos_nodes : name => node
    if node.machine_type == "controlplane" && try(node.bootstrap, false)
  }
  talos_configuration_apply_nodes = {
    for name, node in local.talos_nodes : name => node
    if node.configuration_delivery == "api"
  }
  talos_recovery_clusters = {
    for cluster_name, cluster in local.talos_clusters : cluster_name => cluster
    if anytrue([
      for node in values(cluster.nodes) :
      node.machine_type == "controlplane" && try(node.bootstrap, false)
    ])
  }
  talos_control_plane_endpoints = {
    for cluster_name, cluster in local.talos_clusters : cluster_name => [
      for node_name, node in cluster.nodes : local.talos_connection_endpoints[node_name]
      if node.machine_type == "controlplane"
    ]
  }
  talos_worker_endpoints = {
    for cluster_name, cluster in local.talos_clusters : cluster_name => [
      for node_name, node in cluster.nodes : local.talos_connection_endpoints[node_name]
      if node.machine_type == "worker"
    ]
  }

  machine_access = {
    for name, machine in local.machines : name => {
      url = try(machine.management_port, null) != null ? "https://${local.machine_fqdns[name]}:${machine.management_port}" : try(machine.ssh.port, null) != null ? "ssh://${local.machine_fqdns[name]}:${machine.ssh.port}" : "https://${local.machine_fqdns[name]}"
      username = try(
        machine.ssh.user,
        machine.platform == "talos" ? "talosctl" : name,
      )
    }
  }

  virtual_machine_devices = merge([
    for virtual_machine_name, virtual_machine in local.virtual_machines : {
      "${virtual_machine_name}/boot" = {
        attributes = {
          path = "/dev/zvol/${truenas_zvol.virtual_machine_boot[virtual_machine_name].id}"
          type = "VIRTIO"
        }
        dtype           = "DISK"
        order           = 1000
        virtual_machine = virtual_machine_name
      }
      "${virtual_machine_name}/cdrom" = {
        attributes = {
          path = join("/", [
            trimsuffix(virtual_machine.boot.iso_directory, "/"),
            "talos-${local.talos_schematic_ids[local.machines[virtual_machine_name].cluster]}-${local.clusters[local.machines[virtual_machine_name].cluster].talos_version}.iso",
          ])
        }
        dtype           = "CDROM"
        order           = 1001
        virtual_machine = virtual_machine_name
      }
      "${virtual_machine_name}/network" = {
        attributes = {
          mac = local.machines[virtual_machine_name].mac_address
          nic_attach = local.networks[
            local.machines[virtual_machine_name].location
          ].interfaces[local.machines[virtual_machine_name].network].bridge
          type = "VIRTIO"
        }
        dtype           = "NIC"
        order           = 1002
        virtual_machine = virtual_machine_name
      }
    }
  ]...)
}
