locals {
  dns_machine_services = merge([
    for machine_name, machine in local.machines : {
      for service_name, service in try(machine.services, {}) : "${machine_name}/${service_name}" => {
        hostname = service.hostname
        machine  = machine_name
        zone     = one([for zone in local.cloudflare_zones : zone if endswith(".${service.hostname}", ".${zone}")])
      }
      if try(service.dns_record, false)
    }
  ]...)

  dns_record_sets = {
    for record in values(local.dns_records) :
    "${record.zone}/${record.name}" => record...
  }

  dns_record_sets_conflicting_cname = [
    for record_set, records in local.dns_record_sets : record_set
    if contains([for record in records : record.type], "CNAME") && length(records) > 1
  ]

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
      for name, machine in local.machines : "machine/${name}/ingress" => {
        content = local.machine_fqdns[name]
        name    = "*.${local.machine_fqdns[name]}"
        type    = "CNAME"
        zone    = local.domains.infrastructure
      }
      if can(machine.ingress)
    },
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
      for cluster_name, cluster in local.clusters : "cluster/${cluster_name}/api" => {
        content = try(local.talos_nodes[cluster.api_node].tailscale_address, local.talos_nodes[cluster.api_node].address)
        name    = "api.${cluster_name}.${local.domains.services}"
        type    = "A"
        zone    = local.domains.services
      }
    },
    {
      for cluster_name, cluster in local.clusters : "cluster/${cluster_name}/public" => {
        content = oci_core_instance.node[try(cluster.public_node, cluster.api_node)].public_ip
        name    = "public.${cluster_name}.${local.domains.services}"
        type    = "A"
        zone    = local.domains.services
      }
      if try(local.machines[try(cluster.public_node, cluster.api_node)].oci.assign_public_ip, false)
    },
    {
      for cluster_name in keys(local.clusters) : "cluster/${cluster_name}/tailscale" => {
        content = local.tailscale_cluster_addresses[cluster_name].ipv4
        name    = "*.${cluster_name}.${local.domains.services}"
        type    = "A"
        zone    = local.domains.services
      }
      if try(local.tailscale_cluster_addresses[cluster_name].ipv4, null) != null
    },
    {
      for cluster_name in keys(local.clusters) : "cluster/${cluster_name}/tailscale-aaaa" => {
        content = local.tailscale_cluster_addresses[cluster_name].ipv6
        name    = "*.${cluster_name}.${local.domains.services}"
        type    = "AAAA"
        zone    = local.domains.services
      }
      if try(local.tailscale_cluster_addresses[cluster_name].ipv6, null) != null
    },
    {
      for cluster_name, consumer in local.cloudflare_consumers_tunnel : "cluster/${cluster_name}/tunnel" => {
        content = "${cloudflare_zero_trust_tunnel_cloudflared.cluster[cluster_name].id}.cfargotunnel.com"
        name    = "tunnel.${cluster_name}.${local.domains.services}"
        type    = "CNAME"
        zone    = local.domains.services
      }
      if consumer.is_cluster
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
      for service_key, service in local.dns_machine_services : "service/${service_key}" => {
        content = local.machine_fqdns[service.machine]
        name    = service.hostname
        type    = "CNAME"
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
      for name, tailscale_name in local.tailscale_machine_device_names : "machine/${name}/a" => {
        content = local.tailscale_device_addresses[tailscale_name].ipv4
        name    = local.machine_fqdns[name]
        type    = "A"
        zone    = local.domains.infrastructure
      }
      if try(local.tailscale_device_addresses[tailscale_name].ipv4, null) != null
    },
    {
      for name, tailscale_name in local.tailscale_machine_device_names : "machine/${name}/aaaa" => {
        content = local.tailscale_device_addresses[tailscale_name].ipv6
        name    = local.machine_fqdns[name]
        type    = "AAAA"
        zone    = local.domains.infrastructure
      }
      if try(local.tailscale_device_addresses[tailscale_name].ipv6, null) != null
    },
  )

  dns_records_fastmail = {
    for source_file in local.dns_zone_files : source_file.zone.name => [
      for record in local.provider_settings.dns.fastmail : merge(record, {
        content = replace(record.content, "{domain}", source_file.zone.name)
      })
    ]
    if contains(try(source_file.zone.providers, []), "fastmail")
  }

  dns_records_manual = {
    for entry in flatten([
      for source_file in local.dns_zone_files : [
        for record in concat(
          try(source_file.zone.records, []),
          try(local.dns_records_fastmail[source_file.zone.name], []),
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
          zone   = source_file.zone.name
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

  dns_zone_files = [
    for file_path in fileset(path.module, "data/dns/*.yaml") : {
      file_name = trimsuffix(basename(file_path), ".yaml")
      zone      = yamldecode(file("${path.module}/${file_path}"))
    }
  ]

}

resource "terraform_data" "dns_validation" {
  lifecycle {
    precondition {
      condition     = length(local.dns_record_sets_conflicting_cname) == 0
      error_message = "DNS CNAME records cannot coexist with other records at the same name: ${join(", ", local.dns_record_sets_conflicting_cname)}"
    }
  }
}
