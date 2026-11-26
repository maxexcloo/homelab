data "truenas_group" "monitoring" {
  for_each = local.truenas_monitoring_hosts

  name     = "truenas_readonly_administrators"
  provider = truenas.hosts[each.key]
}

locals {
  # A bridge without a host address gives the Talos container its own port.
  truenas_container_bridges = {
    for interface in local.machine_interface_assignments : interface.machine => interface
    if can(local.truenas_hosts[interface.machine]) && interface.bridge != null
  }

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
        path               = path
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

  truenas_init_scripts = merge([
    for target, host in local.truenas_hosts : {
      for name, script in try(host.init_scripts, {}) : "${target}/${name}" => merge(script, { target = target })
    }
  ]...)

  truenas_monitoring_hosts = {
    for service in values(local.machine_services) : service.machine => service
    if can(local.truenas_hosts[service.machine]) && try(service.widget.type, null) == "truenas"
  }

  truenas_s3_backup_hosts = {
    for name in keys(local.truenas_s3_hosts) : local.machine_clusters[name] => name
    if can(local.machine_clusters[name])
  }

  truenas_s3_hosts = {
    for name, host in local.truenas_hosts : name => host.services.s3
    if can(host.services.s3.username)
  }

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
            destination = local.talos_dataset_root
            options     = ["rbind", "rslave", "rw"]
            source      = local.talos_dataset_root
            type        = "bind"
          }]
          extraConfig = {
            # Image GC can only fail without dataset capacity (see below); 100 disables it.
            imageGCHighThresholdPercent = 100
            imageGCLowThresholdPercent  = 98
            # The stock 15% eviction reserve is too much of a shared model disk; keep 1% free.
            # Setting evictionHard replaces every default signal, so all of them are listed.
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
              memory = "${floor(local.truenas_hosts[name].memory_bytes / 1024) - container.memory_gib * 1024 * 1024}Ki"
            }
          }
        }
      }
    }
  }

  truenas_talos_container_storage_paths = {
    for name, container in local.truenas_talos_containers : name => truenas_dataset.top_level["${name}/${container.dataset}"].mountpoint
  }

  truenas_talos_containers = {
    for name, node in local.talos_nodes : name => merge(node, node.container, {
      device_name = "${local.machine_hostnames[name]}-talos"
      image       = "ghcr.io/siderolabs/talos:${local.clusters[node.cluster].talos_version}"
      name        = local.machine_hostnames[name]
      subnet_cidr = one([
        for subnet in try(local.networks[local.machines[name].network].subnets, {}) : subnet.cidr
        if cidrcontains(subnet.cidr, node.address)
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

resource "truenas_api_key" "monitoring" {
  for_each = local.truenas_monitoring_hosts

  name     = "Homepage Monitoring"
  provider = truenas.hosts[each.key]
  username = truenas_user.monitoring[each.key].username
}

resource "truenas_app" "controlplane" {
  for_each = local.truenas_talos_containers

  custom_app = true
  name       = "talos"
  provider   = truenas.hosts[each.key]

  custom_compose_config_string = yamlencode({
    services = {
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
          lan = {
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
              { directory = "tailscale", target = local.talos_container_tailscale_state_directory },
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
              source    = truenas_dataset.top_level["${each.key}/${dataset.name}"].mountpoint
              target    = "${local.talos_dataset_root}/${truenas_dataset.top_level["${each.key}/${dataset.name}"].id}"
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
      lan = {
        driver = "macvlan"
        driver_opts = {
          parent = local.truenas_container_bridges[each.key].bridge
        }
        ipam = {
          config = [{
            gateway = cidrhost(each.value.subnet_cidr, 1)
            subnet  = cidrsubnet(each.value.subnet_cidr, 0, 0)
          }]
        }
      }
      # macvlan cannot reach the host; this bridge gives Tailscale a local peer path.
      local = {
        driver   = "bridge"
        internal = true
      }
    }
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_cronjob" "configured" {
  for_each = local.truenas_cronjobs

  command = can(each.value.smart_test) ? (
    "midclt call disk.smart_test ${each.value.smart_test} '${jsonencode(local.truenas_hosts[each.value.target].smart_test_disks)}'"
  ) : each.value.command

  description = try(each.value.description, null)
  provider    = truenas.hosts[each.value.target]
  stderr      = try(each.value.stderr, null)
  user        = each.value.user

  schedule = {
    dom    = "*"
    dow    = each.value.schedule_dow
    hour   = try(each.value.schedule_hour, "*")
    minute = try(each.value.schedule_minute, "0")
    month  = "*"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_dataset" "nested" {
  for_each = local.truenas_datasets_child

  name     = "${truenas_dataset.top_level[each.value.parent_dataset_key].name}/${each.value.name}"
  provider = truenas.hosts[each.value.target]
  quota    = try(each.value.quota, null)

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_dataset" "top_level" {
  for_each = local.truenas_datasets_root

  name     = each.value.path
  provider = truenas.hosts[each.value.target]
  quota    = try(each.value.quota, null)

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_init_shutdown_script" "host" {
  for_each = local.truenas_init_scripts

  command  = each.value.command
  comment  = each.value.comment
  provider = truenas.hosts[each.value.target]
  timeout  = each.value.timeout
  type     = each.value.type
  when     = each.value.when

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_mail" "host" {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if contains(local.resend_hosts, name)
  }

  fromemail       = "${each.value.network}-${local.machine_hostnames[each.key]}@${local.domains.infrastructure}"
  fromname        = "${each.value.network}-${local.machine_hostnames[each.key]}"
  outgoingserver  = "smtp.resend.com"
  pass            = resend_api_key.host[each.key].token
  pass_wo_version = parseint(substr(sha256(resend_api_key.host[each.key].id), 0, 12), 16)
  port            = 587
  provider        = truenas.hosts[each.key]
  security        = "TLS"
  smtp            = true
  user            = "resend"
}

resource "truenas_network_config" "global" {
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

resource "truenas_network_interface" "talos_bridge" {
  for_each = local.truenas_container_bridges

  aliases        = []
  bridge_members = [truenas_network_interface.talos_uplink[each.key].name]
  ipv4_dhcp      = false
  ipv6_auto      = false
  name           = each.value.bridge
  provider       = truenas.hosts[each.key]
  type           = "BRIDGE"

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_network_interface" "talos_uplink" {
  for_each = local.truenas_container_bridges

  aliases   = []
  ipv4_dhcp = false
  ipv6_auto = false
  name      = each.value.name
  provider  = truenas.hosts[each.key]
  type      = "PHYSICAL"

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_periodic_snapshot_task" "pool" {
  for_each = local.truenas_snapshots

  dataset        = each.value.dataset
  exclude        = try(each.value.exclude, null)
  lifetime_unit  = each.value.lifetime_unit
  lifetime_value = each.value.lifetime_value
  naming_schema  = each.value.naming_schema
  provider       = truenas.hosts[each.value.target]
  recursive      = try(each.value.recursive, null)

  schedule = {
    dom    = try(each.value.schedule_dom, "*")
    dow    = "*"
    hour   = "0"
    minute = "0"
    month  = "*"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_s3_access_key" "backups" {
  for_each = local.truenas_s3_backup_hosts

  name     = "Kubelab ${upper(each.key)} Backups"
  provider = truenas.hosts[each.value]
  username = truenas_user.backup_storage[each.value].username

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_service" "backup_storage" {
  for_each = {
    for name, host in local.truenas_hosts : name => host
    if can(host.services.s3)
  }

  enabled  = true
  name     = "s3"
  provider = truenas.hosts[each.key]

  depends_on = [truenas_dataset.top_level]
}

resource "truenas_service" "configured" {
  for_each = local.truenas_services

  enabled  = each.value.enabled
  name     = each.value.service
  provider = truenas.hosts[each.value.target]
}

resource "truenas_smb_config" "global" {
  for_each = {
    for name, host in local.truenas_hosts : name => host.smb
    if can(host.smb)
  }

  aapl_extensions = each.value.aapl_extensions
  netbiosname     = upper(local.machine_hostnames[each.key])
  provider        = truenas.hosts[each.key]
}

resource "truenas_smb_share" "dataset" {
  for_each = local.truenas_smb_shares

  # Preserve TrueNAS enumeration; the pinned provider defaults it to false.
  abe      = true
  name     = each.value.name
  options  = try(each.value.options, null)
  path     = merge(truenas_dataset.nested, truenas_dataset.top_level)[each.key].mountpoint
  provider = truenas.hosts[each.value.target]
  purpose  = try(each.value.purpose, "DEFAULT_SHARE")

  depends_on = [truenas_smb_config.global]

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_ssh_config" "global" {
  for_each = {
    for name, host in local.truenas_hosts : name => host.ssh
    if can(host.ssh)
  }

  passwordauth = each.value.passwordauth
  provider     = truenas.hosts[each.key]
  tcpfwd       = each.value.tcpfwd
}

resource "truenas_tunable" "configured" {
  for_each = local.truenas_tunables

  provider = truenas.hosts[each.value.target]
  type     = each.value.type
  value    = each.value.value
  var      = each.value.var

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_ups_config" "global" {
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

resource "truenas_user" "backup_storage" {
  for_each = local.truenas_s3_hosts

  full_name         = "Kubernetes Backups"
  group_create      = true
  password_disabled = true
  provider          = truenas.hosts[each.key]
  shell             = "/usr/sbin/nologin"
  smb               = false
  username          = each.value.username

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_user" "monitoring" {
  for_each = local.truenas_monitoring_hosts

  full_name         = "Homepage Monitoring"
  group             = data.truenas_group.monitoring[each.key].id
  password_disabled = true
  provider          = truenas.hosts[each.key]
  shell             = "/usr/sbin/nologin"
  smb               = false
  username          = "homepage"
}
