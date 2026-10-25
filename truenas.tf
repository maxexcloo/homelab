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
    for target, storage in local.truenas_storage : {
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

  truenas_host_services_prefix_lengths = {
    for name, host in local.truenas_hosts_services : name => tonumber(split(
      "/",
      local.networks[host.machine.network].subnets[
        local.truenas_machine_interfaces_by_mac[lower(host.interface.mac_address)].subnet
      ].cidr,
    )[1])
  }

  truenas_hosts = {
    for name, machine in local.machines : name => machine
    if machine.platform == "truenas"
  }

  truenas_hosts_ingress = {
    for name, host in local.truenas_hosts : name => host.ingress
    if can(host.ingress)
  }

  truenas_hosts_services = {
    for name, interfaces in {
      for name, machine in local.truenas_hosts : name => [
        for interface in machine.interfaces : interface
        if try(interface.bridge, null) != null
      ]
      } : name => {
      interface = interfaces[0]
      machine   = local.truenas_hosts[name]
    }
    if length(interfaces) == 1
  }

  truenas_machine_interfaces_by_mac = {
    for interface in local.machine_interface_assignments : interface.mac => interface
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
    for target, storage in local.truenas_storage : {
      for name, snapshot in try(storage.snapshots, {}) : "${target}/${name}" => merge(snapshot, { target = target })
    }
  ]...)

  truenas_storage = local.storage.truenas

  truenas_talos_container_storage_paths = {
    for name, container in local.truenas_talos_containers : name => truenas_dataset.root["${name}/${container.dataset}"].mount_point
  }

  truenas_talos_containers = {
    for name, container in local.talos_containers : name => container
    if can(local.truenas_hosts[name])
  }

  truenas_tunables = merge([
    for target, host in local.truenas_hosts : {
      for name, tunable in try(host.tunables, {}) : "${target}/${name}" => merge(tunable, { target = target, var = name })
    }
  ]...)
}

resource "truenas_app" "ingress" {
  for_each = local.truenas_hosts_ingress

  app_name          = "traefik"
  provider          = truenas.hosts[each.key]
  remove_images     = false
  remove_ix_volumes = false

  custom_compose = yamlencode({
    configs = {
      dynamic = {
        content = yamlencode({
          http = {
            middlewares = {
              private = {
                ipAllowList = {
                  sourceRange = concat(
                    values(local.tailscale_address_ranges),
                    [for subnet in values(local.networks[local.machines[each.key].network].subnets) : cidrsubnet(subnet.cidr, 0, 0)],
                  )
                }
              }
            }
          }
          tls = {
            certificates = [{
              certFile = "/etc/certificates/${each.value.certificate}.crt"
              keyFile  = "/etc/certificates/${each.value.certificate}.key"
            }]
          }
        })
      }
      static = {
        content = yamlencode({
          entryPoints = {
            websecure = {
              address = ":${each.value.port}"
              http = {
                middlewares = ["private@file"]
                tls         = {}
              }
            }
          }
          providers = {
            docker = {
              defaultRule      = "Host(`{{ index .Labels \"com.docker.compose.service\" }}.${local.machine_fqdns[each.key]}`)"
              exposedByDefault = false
              useBindPortIP    = true
            }
            file = {
              filename = "/etc/traefik/dynamic.yaml"
            }
          }
        })
      }
    }
    services = {
      traefik = {
        image        = each.value.image
        network_mode = "host"
        restart      = "unless-stopped"
        configs = [
          { source = "static", target = "/etc/traefik/traefik.yaml" },
          { source = "dynamic", target = "/etc/traefik/dynamic.yaml" },
        ]
        # Host-network apps must resolve back to this network namespace.
        extra_hosts  = ["host.docker.internal:127.0.0.1"]
        security_opt = ["no-new-privileges:true"]
        volumes = [
          {
            read_only = true
            source    = "/etc/certificates"
            target    = "/etc/certificates"
            type      = "bind"
          },
          {
            read_only = true
            source    = "/var/run/docker.sock"
            target    = "/var/run/docker.sock"
            type      = "bind"
          },
        ]
      }
    }
  })
}

resource "truenas_app" "talos_container" {
  for_each = local.truenas_talos_containers

  app_name      = each.value.app_name
  provider      = truenas.hosts[each.key]
  remove_images = false

  custom_compose = yamlencode({
    services = {
      tailscale = {
        cap_add      = ["NET_ADMIN", "NET_RAW"]
        depends_on   = ["talos"]
        devices      = ["/dev/net/tun:/dev/net/tun"]
        image        = local.talos_container_tailscale_image
        network_mode = "service:talos"
        restart      = "unless-stopped"
        environment = {
          TS_AUTHKEY    = tailscale_tailnet_key.talos_container[each.key].key
          TS_AUTH_ONCE  = "true"
          TS_EXTRA_ARGS = "--accept-dns=false"
          TS_HOSTNAME   = each.value.device_name
          TS_ROUTES     = join(",", each.value.tailscale_routes)
          TS_STATE_DIR  = "/var/lib/tailscale"
          TS_USERSPACE  = "false"
        }
        volumes = [{
          source = "${local.truenas_talos_container_storage_paths[each.key]}/tailscale"
          target = "/var/lib/tailscale"
          type   = "bind"
          bind = {
            create_host_path = true
          }
        }]
      }
      talos = {
        cgroup = "private"
        # Keep private service DNS on its public Tailscale records rather than UniFi LAN overrides.
        dns          = ["1.1.1.1", "1.0.0.1"]
        hostname     = each.value.name
        image        = "ghcr.io/siderolabs/talos:${local.clusters[each.value.cluster].talos_version}"
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
          parent = local.truenas_hosts_services[each.key].interface.bridge
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

  command         = each.value.command
  description     = try(each.value.description, null)
  provider        = truenas.hosts[each.value.target]
  schedule_dow    = each.value.schedule_dow
  schedule_hour   = try(each.value.schedule_hour, null)
  schedule_minute = try(each.value.schedule_minute, null)
  stderr          = try(each.value.stderr, null)
  user            = each.value.user
}

resource "truenas_cronjob" "ingress_certificate_reload" {
  for_each = local.truenas_hosts_ingress

  # Signal from inside the container; docker kill marks it manually stopped, so it stays down after a Docker restart.
  command         = "docker ps --filter label=com.docker.compose.project=ix-${truenas_app.ingress[each.key].app_name} --quiet | xargs --no-run-if-empty -I {} docker exec {} kill -HUP 1"
  description     = "Reload Traefik Native Certificates"
  enabled         = true
  provider        = truenas.hosts[each.key]
  schedule_dom    = "*"
  schedule_dow    = "*"
  schedule_hour   = "*"
  schedule_minute = "0"
  schedule_month  = "*"
  stderr          = false
  stdout          = true
  user            = "root"
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
  name           = each.value.interface.bridge
  provider       = truenas.hosts[each.key]
  rollback       = true
  type           = "BRIDGE"

  aliases = [
    {
      address = each.value.interface.address
      netmask = local.truenas_host_services_prefix_lengths[each.key]
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
  name      = each.value.interface.name
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

  type     = each.value.type
  provider = truenas.hosts[each.value.target]
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
