locals {
  dns_machine_services = merge([
    for machine_name, machine in local.machines : {
      for service_name, service in try(machine.services, {}) : "${machine_name}/${service_name}" => {
        content  = try(service.dns_lan, false) ? local.machine_private_ipv4_addresses[machine_name] : local.machine_fqdns[machine_name]
        hostname = service.hostname
        machine  = machine_name
        type     = try(service.dns_lan, false) ? "A" : "CNAME"
        zone     = one([for zone in local.cloudflare_zones : zone if endswith(".${service.hostname}", ".${zone}")])
      }
      if try(service.dns_record, false)
    }
  ]...)

  dns_private_proxy_ingresses = {
    for cluster_name in keys(local.clusters) : cluster_name => "private.${cluster_name}.${local.domains.services}"
  }

  dns_private_proxy_names = merge(
    {
      for cluster_name, hostname in local.dns_private_proxy_ingresses : "cluster/${cluster_name}" => {
        cluster  = cluster_name
        hostname = hostname
        zone     = local.domains.services
      }
    },
    {
      for service_key, service in local.dns_private_proxy_services : "service/${service_key}" => {
        cluster  = service.cluster
        hostname = service.hostname
        zone     = local.domains.infrastructure
      }
    },
    {
      for service_key, service in local.dns_private_proxy_services : "alias/${service_key}" => {
        cluster  = service.cluster
        hostname = service.alias
        zone     = local.domains.services
      }
    },
  )

  dns_private_proxy_services = merge([
    for machine_name, machine in local.machines : {
      for service_name, service in try(machine.services, {}) : "${machine_name}/${service_name}" => {
        alias    = "${service_name}-${local.machine_hostnames[machine_name]}.${service.private_proxy}.${local.domains.services}"
        cluster  = service.private_proxy
        hostname = "${service_name}.${local.machine_hostnames[machine_name]}.${local.domains.infrastructure}"
      }
      if can(service.private_proxy)
    }
  ]...)

  dns_records = merge(
    {
      for record_key, record in local.dns_records_derived_specs : record_key => merge(
        {
          comment  = local.managed_comment
          priority = null
          proxied  = false
          ttl      = 1
        },
        record,
      )
    },
    local.dns_records_manual,
  )

  dns_records_derived_specs = merge(
    {
      for record_key, entry in local.dns_records_resend : "resend/${record_key}" => {
        content  = entry.record.value
        name     = "${entry.record.name}.${entry.zone}"
        priority = try(tonumber(entry.record.priority), null)
        type     = entry.record.type
        zone     = entry.zone
      }
    },
    {
      for zone in local.cloudflare_zones : "acme-delegation/${zone}" => {
        content = "_acme-challenge.${zone}.${local.domains.acme}"
        name    = "_acme-challenge.${zone}"
        type    = "CNAME"
        zone    = zone
      }
      if zone != local.domains.acme
    },
    {
      for name, consumer in local.cloudflare_consumers_acme : "acme/${name}" => {
        content = consumer.target_hostname
        name    = "_acme-challenge.${consumer.challenge_hostname}"
        type    = "CNAME"
        zone    = consumer.challenge_zone
      }
      if consumer.challenge_mode == "delegated"
    },
    {
      for cluster_name in keys(local.clusters) : "cluster/${cluster_name}/api" => {
        content = local.talos_cluster_api_addresses[cluster_name]
        name    = "api.${cluster_name}.${local.domains.services}"
        type    = "A"
        zone    = local.domains.services
      }
    },
    {
      for cluster_name, cluster in local.clusters : "cluster/${cluster_name}/public" => {
        content = oci_core_instance.node[cluster.public_node].public_ip
        name    = "public.${cluster_name}.${local.domains.services}"
        type    = "A"
        zone    = local.domains.services
      }
      if try(local.machines[cluster.public_node].oci.assign_public_ip, false)
    },
    {
      for cluster_name, hostname in local.dns_private_proxy_ingresses : "cluster/${cluster_name}/private" => {
        content = local.tailscale_cluster_addresses[cluster_name].ipv4
        name    = hostname
        type    = "A"
        zone    = local.domains.services
      }
    },
    {
      for cluster_name, hostname in local.dns_private_proxy_ingresses : "cluster/${cluster_name}/private-aaaa" => {
        content = local.tailscale_cluster_addresses[cluster_name].ipv6
        name    = hostname
        type    = "AAAA"
        zone    = local.domains.services
      }
    },
    {
      for cluster_name in keys(local.clusters) : "cluster/${cluster_name}/tailscale" => {
        content = local.tailscale_cluster_addresses[cluster_name].ipv4
        name    = "*.${cluster_name}.${local.domains.services}"
        type    = "A"
        zone    = local.domains.services
      }
    },
    {
      for cluster_name in keys(local.clusters) : "cluster/${cluster_name}/tailscale-aaaa" => {
        content = local.tailscale_cluster_addresses[cluster_name].ipv6
        name    = "*.${cluster_name}.${local.domains.services}"
        type    = "AAAA"
        zone    = local.domains.services
      }
    },
    {
      for cluster_name in keys(local.cloudflare_consumers_tunnel) : "cluster/${cluster_name}/tunnel" => {
        content = "${cloudflare_zero_trust_tunnel_cloudflared.cluster[cluster_name].id}.cfargotunnel.com"
        name    = "tunnel.${cluster_name}.${local.domains.services}"
        type    = "CNAME"
        zone    = local.domains.services
      }
      if can(local.clusters[cluster_name])
    },
    {
      for route_key, route in local.cloudflare_tunnel_routes : "tunnel/${route_key}" => {
        content = "${cloudflare_zero_trust_tunnel_cloudflared.cluster[route.consumer].id}.cfargotunnel.com"
        name    = route.hostname
        proxied = true
        type    = "CNAME"
        zone    = route.zone
      }
    },
    {
      for name_key, frontend in local.dns_private_proxy_names : "private-proxy/${name_key}" => {
        content = local.dns_private_proxy_ingresses[frontend.cluster]
        name    = frontend.hostname
        type    = "CNAME"
        zone    = frontend.zone
      }
      if startswith(name_key, "service/") || startswith(name_key, "alias/")
    },
    {
      for name_key, frontend in local.dns_private_proxy_names : "private-proxy-acme/${name_key}" => {
        content = local.cloudflare_consumers_acme[frontend.cluster].target_hostname
        name    = "_acme-challenge.${frontend.hostname}"
        type    = "CNAME"
        zone    = frontend.zone
      }
      if local.cloudflare_consumers_acme[frontend.cluster].challenge_mode == "delegated"
    },
    {
      for service_key, service in local.dns_machine_services : "service/${service_key}" => {
        content = service.content
        name    = service.hostname
        type    = service.type
        zone    = service.zone
      }
    },
    {
      for service_key, service in local.dns_machine_services : "service-acme/${service_key}" => {
        content = local.cloudflare_consumers_acme[service.machine].target_hostname
        name    = "_acme-challenge.${service.hostname}"
        type    = "CNAME"
        zone    = service.zone
      }
      if try(local.cloudflare_consumers_acme[service.machine].challenge_mode, null) == "delegated"
    },
    {
      for name, tailscale_name in local.machine_tailscale_names : "machine/${name}/a" => {
        content = local.tailscale_device_addresses[tailscale_name].ipv4
        name    = local.machine_fqdns[name]
        type    = "A"
        zone    = local.domains.infrastructure
      }
      if try(local.tailscale_device_addresses[tailscale_name].ipv4, null) != null
    },
    {
      for name, tailscale_name in local.machine_tailscale_names : "machine/${name}/aaaa" => {
        content = local.tailscale_device_addresses[tailscale_name].ipv6
        name    = local.machine_fqdns[name]
        type    = "AAAA"
        zone    = local.domains.infrastructure
      }
      if try(local.tailscale_device_addresses[tailscale_name].ipv6, null) != null
    },
    {
      for name, machine in local.machines : "machine/${name}/public-a" => {
        content = try(machine.public_ipv4, oci_core_instance.node[name].public_ip)
        name    = "public.${local.machine_fqdns[name]}"
        type    = "A"
        zone    = local.domains.infrastructure
      }
      if try(machine.public_ipv4, null) != null || try(machine.oci.assign_public_ip, false)
    },
    {
      for name, machine in local.machines : "machine/${name}/public-aaaa" => {
        content = machine.public_ipv6
        name    = "public.${local.machine_fqdns[name]}"
        type    = "AAAA"
        zone    = local.domains.infrastructure
      }
      if try(machine.public_ipv6, null) != null
    },
  )

  dns_records_fastmail = {
    for dns_zone in local.dns_zones : dns_zone.name => [
      for record in local.provider_settings.dns.fastmail : merge(record, {
        content = replace(record.content, "{domain}", dns_zone.name)
      })
    ]
    if contains(try(dns_zone.providers, []), "fastmail")
  }

  dns_records_manual = {
    for entry in flatten([
      for dns_zone in local.dns_zones : [
        for record in concat(
          try(dns_zone.records, []),
          try(local.dns_records_fastmail[dns_zone.name], []),
          ) : {
          key = try(
            record.id,
            join("-", compact([
              record.type,
              replace(record.name, "@", "apex"),
              tostring(try(record.priority, null)),
            ])),
          )
          record = record
          zone   = dns_zone.name
        }
      ]
    ]) :
    "${entry.zone}-manual-${entry.key}" => {
      comment  = local.managed_comment
      content  = entry.record.content
      name     = entry.record.name == "@" ? entry.zone : "${entry.record.name}.${entry.zone}"
      priority = try(entry.record.priority, null)
      proxied  = try(entry.record.proxied, false)
      ttl      = try(entry.record.ttl, 1)
      type     = entry.record.type
      zone     = entry.zone
    }
  }

  dns_records_resend = merge([
    for domain, settings in local.resend_domains : {
      for name, selector in {
        cname = "SPF/CNAME"
        dkim  = "DKIM/TXT"
        mx    = "SPF/MX"
        spf   = "SPF/TXT"
        } : "${domain}/${name}" => {
        zone = domain
        record = one([
          for record in resend_domain.configured[domain].records : record
          if "${record.record}/${record.type}" == selector
        ])
      }
      if name != "cname" || settings.cname
    }
  ]...)

  dns_zones = [
    for file_path in fileset(path.module, "data/dns/*.yaml") : yamldecode(file("${path.module}/${file_path}"))
  ]
}
