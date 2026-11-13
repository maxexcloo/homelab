data "truenas_system_info" "container_host" {
  for_each = local.truenas_talos_containers

  provider = truenas.hosts[each.key]
}

locals {
  truenas_cronjobs = merge([
    for target, host in local.truenas_hosts : {
      for name, job in try(host.cronjobs, {}) : "${target}/${name}" => merge(job, { target = target })
    }
  ]...)

  truenas_datasets = merge([
    for target, storage in local.storage : {
      for path, dataset in storage.datasets : "${target}/${path}" => merge(dataset, {
        name               = basename(path)
        parent_dataset_key = dirname(path) == split("/", path)[0] ? null : "${target}/${dirname(path)}"
        pool               = split("/", path)[0]
        target             = target
      })
    }
  ]...)

  truenas_datasets_child = {
    for key, dataset in local.truenas_datasets : key => dataset
    if dataset.parent_dataset_key != null
  }

  truenas_datasets_root = {
    for key, dataset in local.truenas_datasets : key => dataset
    if dataset.parent_dataset_key == null
  }

  truenas_hosts = {
    for name, machine in local.machines : name => machine
    if machine.platform == "truenas"
  }

  truenas_hosts_services = {
    for interface in local.machine_interface_assignments : interface.machine => merge(interface, {
      prefix_length = tonumber(split("/", local.networks[interface.network].subnets[interface.subnet].cidr)[1])
    })
    if can(local.truenas_hosts[interface.machine]) && interface.bridge != null
  }

  truenas_init_scripts = merge([
    for target, host in local.truenas_hosts : {
      for name, script in try(host.init_scripts, {}) : "${target}/${name}" => merge(script, { target = target })
    }
  ]...)

  truenas_services = merge([
    for target, host in local.truenas_hosts : {
      for service, enabled in try(host.service_settings, {}) : "${target}/${service}" => {
        enabled = enabled
        service = service
        target  = target
      }
    }
  ]...)

  truenas_smb_shares = {
    for key, dataset in local.truenas_datasets : key => merge(dataset.smb, {
      name   = try(dataset.smb.name, dataset.name)
      target = dataset.target
    })
    if can(dataset.smb)
  }

  truenas_snapshots = merge([
    for target, storage in local.storage : {
      for name, snapshot in try(storage.snapshots, {}) : "${target}/${name}" => merge(snapshot, { target = target })
    }
  ]...)

  # Public DNS keeps private service names on their Tailscale records rather than
  # UniFi LAN overrides.
  truenas_talos_container_dns_servers = ["1.1.1.1", "1.0.0.1"]

  truenas_talos_container_kubelet_configurations = {
    for name, container in local.truenas_talos_containers : name => {
      machine = {
        kubelet = {
          image = "ghcr.io/siderolabs/kubelet:${local.clusters[container.cluster].kubernetes_version}"
          extraMounts = [{
            destination = "/var/mnt/datasets"
            options     = ["rbind", "rslave", "rw"]
            source      = "/var/mnt/datasets"
            type        = "bind"
          }]
          extraConfig = {
            # The stock reserves (15% for eviction, image cleanup from 85% used) are 140 GB of a
            # shared 1 TB model disk; keep 1% free instead.
            # Setting evictionHard replaces every default signal, so all of them are listed.
            imageGCHighThresholdPercent = 99
            imageGCLowThresholdPercent  = 98
            evictionHard = {
              "imagefs.available"  = "1%"
              "imagefs.inodesFree" = "5%"
              "memory.available"   = "100Mi"
              "nodefs.available"   = "1%"
              "nodefs.inodesFree"  = "5%"
            }

            # The stock kubelet image cannot report capacity for the host ZFS dataset.
            localStorageCapacityIsolation = false
            kubeReserved = {
              memory = "1Gi"
            }
            systemReserved = {
              memory = "${floor(data.truenas_system_info.container_host[name].physical_memory / 1024) - container.memory_gib * 1024 * 1024}Ki"
            }
          }
        }
      }
    }
  }

  truenas_talos_container_storage_paths = {
    for name, container in local.truenas_talos_containers : name => truenas_dataset.root["${name}/${container.dataset}"].mount_point
  }

  # TrueNAS containers use a Tailscale sidecar, omitting local addresses as Talos nodes do (talos.tf).
  # The router does not hairpin to the NATed endpoint, so same-site peers need the LAN address
  # advertised explicitly or they relay through DERP.
  truenas_talos_container_tailscale_environment = {
    for name, container in local.truenas_talos_containers : name => {
      TS_AUTH_ONCE              = "true"
      TS_AUTHKEY                = tailscale_tailnet_key.talos_container[name].key
      TS_DEBUG_OMIT_LOCAL_ADDRS = "true"
      TS_DEBUG_PRETENDPOINT     = "${container.address}:${local.truenas_talos_container_tailscale_port}"
      TS_HOSTNAME               = container.device_name
      TS_SERVE_CONFIG           = local.talos_tailscale_serve_config_path
      TS_STATE_DIR              = local.truenas_talos_container_tailscale_state_directory
      TS_TAILSCALED_EXTRA_ARGS  = "--port=${local.truenas_talos_container_tailscale_port}"
      TS_USERSPACE              = "false"
    }
  }

  truenas_talos_container_tailscale_port = 41641

  truenas_talos_container_tailscale_state_directory = "/var/lib/tailscale"

  truenas_talos_containers = {
    for name, node in local.talos_nodes : name => merge(node, node.container, {
      device_name = "${node.cluster}-${local.machine_hostnames[name]}-talos"
      image       = "ghcr.io/siderolabs/talos:${local.clusters[node.cluster].talos_version}"
      name        = local.machine_hostnames[name]
      network_key = one([
        for key, network in local.unifi_networks : key
        if startswith(key, "${local.machines[name].network}/") && cidrcontains(network.subnet, node.address)
      ])
    })
    if node.configuration_delivery == "container"
  }

  truenas_tunables = merge([
    for target, host in local.truenas_hosts : {
      for name, tunable in try(host.tunables, {}) : "${target}/${name}" => merge(tunable, { target = target, var = name })
    }
  ]...)
}

resource "truenas_app" "talos_container" {
  for_each = local.truenas_talos_containers

  app_name      = "talos"
  provider      = truenas.hosts[each.key]
  remove_images = false

  custom_compose = yamlencode({
    configs = {
      tailscale-serve = {
        content = local.tailscale_cluster_serve_configs[each.value.cluster]
      }
    }
    services = {
      tailscale = {
        cap_add = ["NET_ADMIN", "NET_RAW"]
        configs = [{
          source = "tailscale-serve"
          target = local.talos_tailscale_serve_config_path
        }]
        depends_on   = ["talos"]
        devices      = ["/dev/net/tun:/dev/net/tun"]
        image        = local.versions.images.tailscale
        network_mode = "service:talos"
        restart      = "unless-stopped"
        environment  = local.truenas_talos_container_tailscale_environment[each.key]
        volumes = [{
          source = "${local.truenas_talos_container_storage_paths[each.key]}/tailscale"
          target = local.truenas_talos_container_tailscale_state_directory
          type   = "bind"
          bind = {
            create_host_path = true
          }
        }]
      }
      talos = {
        cgroup       = "private"
        dns          = local.truenas_talos_container_dns_servers
        hostname     = each.value.name
        image        = each.value.image
        mem_limit    = "${each.value.memory_gib}g"
        privileged   = true
        read_only    = true
        restart      = "unless-stopped"
        security_opt = ["seccomp=unconfined"]
        tmpfs        = ["/run", "/system", "/tmp"]
        environment = {
          PLATFORM = "container"
        }
        networks = {
          local = {}
          services = {
            ipv4_address = each.value.address
            mac_address  = each.value.mac
          }
        }
        # Host mounts propagate into Talos but never back, so restarts cannot stack mounts on the host.
        volumes = concat(
          [
            for volume in [
              { directory = "controlplane/opt", target = "/opt" },
              { directory = "controlplane/state", target = "/system/state" },
              { directory = "controlplane/var", target = "/var" },
              ] : {
              source = "${local.truenas_talos_container_storage_paths[each.key]}/${volume.directory}"
              target = volume.target
              type   = "bind"
              bind = {
                create_host_path = true
                propagation      = "rslave"
              }
            }
          ],
          [
            for dataset in each.value.datasets : {
              source    = truenas_dataset.root["${each.key}/${dataset.name}"].mount_point
              target    = "/var/mnt/datasets/${truenas_dataset.root["${each.key}/${dataset.name}"].id}"
              type      = "bind"
              read_only = try(dataset.read_only, false)
              bind = {
                propagation = "rslave"
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
          parent = local.truenas_hosts_services[each.key].bridge
        }
        ipam = {
          config = [{
            gateway = cidrhost(local.unifi_networks[each.value.network_key].subnet, 1)
            subnet  = cidrsubnet(local.unifi_networks[each.value.network_key].subnet, 0, 0)
          }]
        }
      }
    }
  })
}

resource "truenas_cronjob" "host" {
  for_each = local.truenas_cronjobs

  command = can(each.value.smart_test) ? (
    "midclt call disk.smart_test ${each.value.smart_test} '${jsonencode(local.truenas_hosts[each.value.target].smart_test_disks)}'"
  ) : each.value.command

  description     = try(each.value.description, null)
  provider        = truenas.hosts[each.value.target]
  schedule_dow    = each.value.schedule_dow
  schedule_hour   = try(each.value.schedule_hour, null)
  schedule_minute = try(each.value.schedule_minute, null)
  stderr          = try(each.value.stderr, null)
  user            = each.value.user
}

resource "truenas_dataset" "child" {
  for_each = local.truenas_datasets_child

  name           = each.value.name
  parent_dataset = truenas_dataset.root[each.value.parent_dataset_key].name
  pool           = each.value.pool
  provider       = truenas.hosts[each.value.target]
  quota          = try(each.value.quota, null)

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_dataset" "root" {
  for_each = local.truenas_datasets_root

  name     = each.value.name
  pool     = each.value.pool
  provider = truenas.hosts[each.value.target]
  quota    = try(each.value.quota, null)

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_init_script" "host" {
  for_each = local.truenas_init_scripts

  command  = each.value.command
  comment  = each.value.comment
  provider = truenas.hosts[each.value.target]
  timeout  = each.value.timeout
  type     = each.value.type
  when     = each.value.when
}

resource "truenas_mail_config" "host" {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if contains(local.resend_hosts, name)
  }

  fromemail      = "${each.value.network}-${local.machine_hostnames[each.key]}@${local.domains.infrastructure}"
  fromname       = "${each.value.network}-${local.machine_hostnames[each.key]}"
  outgoingserver = "smtp.resend.com"
  pass           = resend_api_key.host[each.key].token
  port           = 587
  provider       = truenas.hosts[each.key]
  security       = "TLS"
  smtp           = true
  user           = "resend"
}

resource "truenas_network_config" "host" {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if can(host.network_configuration)
  }

  domain      = "${each.value.network}.${local.domains.infrastructure}"
  hostname    = local.machine_hostnames[each.key]
  ipv4gateway = cidrhost(local.networks[each.value.network].subnets.default.cidr, 1)
  ipv6gateway = each.value.network_configuration.ipv6gateway
  nameserver1 = cidrhost(local.networks[each.value.network].subnets.default.cidr, 1)
  provider    = truenas.hosts[each.key]
}

resource "truenas_network_interface" "services_bridge" {
  for_each = local.truenas_hosts_services

  bridge_members = [truenas_network_interface.services_physical[each.key].name]
  ipv4_dhcp      = false
  ipv6_auto      = false
  name           = each.value.bridge
  provider       = truenas.hosts[each.key]
  rollback       = true
  type           = "BRIDGE"

  aliases = [
    {
      address = each.value.address
      netmask = each.value.prefix_length
      type    = "INET"
    },
  ]

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_network_interface" "services_physical" {
  for_each = local.truenas_hosts_services

  aliases   = []
  ipv4_dhcp = false
  ipv6_auto = false
  name      = each.value.name
  provider  = truenas.hosts[each.key]
  rollback  = true
  type      = "PHYSICAL"

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_service" "host" {
  for_each = local.truenas_services

  enable   = each.value.enabled
  provider = truenas.hosts[each.value.target]
  service  = each.value.service
}

resource "truenas_service" "s3" {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if can(host.services.s3)
  }

  enable   = true
  provider = truenas.hosts[each.key]
  service  = "s3"

  depends_on = [truenas_dataset.root]
}

resource "truenas_share_smb" "dataset" {
  for_each = local.truenas_smb_shares

  # Preserve TrueNAS enumeration; the pinned provider defaults it to false.
  abe      = true
  name     = each.value.name
  options  = try(each.value.options, null)
  path     = merge(truenas_dataset.child, truenas_dataset.root)[each.key].mount_point
  provider = truenas.hosts[each.value.target]
  purpose  = try(each.value.purpose, null)

  depends_on = [truenas_smb_config.host]

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_smb_config" "host" {
  for_each = {
    for name, host in local.truenas_hosts : name => host.smb
    if can(host.smb)
  }

  aapl_extensions = each.value.aapl_extensions
  netbiosname     = upper(local.machine_hostnames[each.key])
  provider        = truenas.hosts[each.key]
}

resource "truenas_snapshot_task" "pool" {
  for_each = local.truenas_snapshots

  dataset        = each.value.dataset
  exclude        = try(each.value.exclude, null)
  lifetime_unit  = try(each.value.lifetime_unit, null)
  lifetime_value = try(each.value.lifetime_value, null)
  naming_schema  = try(each.value.naming_schema, null)
  provider       = truenas.hosts[each.value.target]
  recursive      = try(each.value.recursive, null)
  schedule_dom   = try(each.value.schedule_dom, null)
}

resource "truenas_ssh_config" "host" {
  for_each = {
    for name, host in local.truenas_hosts : name => host.ssh
    if can(host.ssh)
  }

  passwordauth = each.value.passwordauth
  provider     = truenas.hosts[each.key]
  tcpfwd       = each.value.tcpfwd
}

resource "truenas_tunable" "host" {
  for_each = local.truenas_tunables

  provider = truenas.hosts[each.value.target]
  type     = each.value.type
  value    = each.value.value
  var      = each.value.var
}

resource "truenas_ups_config" "host" {
  for_each = {
    for name, host in local.truenas_hosts : name => host.ups
    if can(host.ups)
  }

  driver     = each.value.driver
  port       = each.value.port
  provider   = truenas.hosts[each.key]
  remotehost = each.value.remotehost
  shutdown   = each.value.shutdown
}

resource "truenas_user" "s3" {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if can(host.services.s3.username)
  }

  full_name         = "Kubernetes Backups"
  group_create      = true
  password_disabled = true
  provider          = truenas.hosts[each.key]
  shell             = "/usr/sbin/nologin"
  smb               = false
  username          = each.value.services.s3.username
}
