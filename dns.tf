locals {
  dns_record_entries_manual_by_key = {
    for entry in flatten([
      for source_file in local.dns_zone_files : [
        for record in try(source_file.zone.records, []) : {
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
    "${entry.zone}-manual-${entry.key}" => entry...
  }

  dns_record_keys_duplicate = [
    for record_key, entries in local.dns_record_entries_manual_by_key : record_key
    if length(entries) > 1
  ]

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
          comment  = "Managed by OpenTofu"
          priority = null
          proxied  = false
          ttl      = 300
        },
        record,
      )
    },
    local.dns_records_manual,
  )

  dns_records_derived_specs = merge(
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
        content = local.machines[cluster.api_node].address
        name    = "api.${cluster_name}.${local.domains.services}"
        type    = "A"
        zone    = local.domains.services
      }
    },
    {
      for cluster_name, cluster in local.clusters : "cluster/${cluster_name}/public" => {
        content = oci_core_instance.node[cluster.api_node].public_ip
        name    = "public.${cluster_name}.${local.domains.services}"
        type    = "A"
        zone    = local.domains.services
      }
      if try(local.machines[cluster.api_node].oci.assign_public_ip, false)
    },
    {
      for cluster_name in keys(local.clusters) : "cluster/${cluster_name}/tailscale" => {
        content = local.tailscale_device_ipv4[cluster_name]
        name    = "*.${cluster_name}.${local.domains.services}"
        type    = "A"
        zone    = local.domains.services
      }
      if try(local.tailscale_device_ipv4[cluster_name], null) != null
    },
    {
      for cluster_name in keys(local.clusters) : "cluster/${cluster_name}/tailscale-aaaa" => {
        content = local.tailscale_device_ipv6[cluster_name]
        name    = "*.${cluster_name}.${local.domains.services}"
        type    = "AAAA"
        zone    = local.domains.services
      }
      if try(local.tailscale_device_ipv6[cluster_name], null) != null
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
      for name in keys(local.machines) : "machine/${name}/a" => {
        content = local.tailscale_device_ipv4[name]
        name    = local.machine_fqdns[name]
        type    = "A"
        zone    = local.domains.infrastructure
      }
    },
    {
      for name in keys(local.machines) : "machine/${name}/aaaa" => {
        content = local.tailscale_device_ipv6[name]
        name    = local.machine_fqdns[name]
        type    = "AAAA"
        zone    = local.domains.infrastructure
      }
    },
  )

  dns_records_manual = {
    for record_key, entries in local.dns_record_entries_manual_by_key : record_key => {
      comment  = try(entries[0].record.comment, "OpenTofu Managed")
      content  = entries[0].record.content
      name     = entries[0].record.name == "@" ? entries[0].zone : "${entries[0].record.name}.${entries[0].zone}"
      priority = try(entries[0].record.priority, null)
      proxied  = try(entries[0].record.proxied, false)
      ttl      = try(entries[0].record.ttl, 1)
      type     = entries[0].record.type
      zone     = entries[0].zone
    }
  }

  dns_zone_file_names_mismatched = [
    for source_file in local.dns_zone_files :
    "${source_file.file_name} -> ${source_file.zone.name}"
    if source_file.file_name != source_file.zone.name
  ]

  dns_zone_files = [
    for file_path in fileset(path.module, "data/dns/*.yaml") : {
      file_name = trimsuffix(basename(file_path), ".yaml")
      zone      = yamldecode(file("${path.module}/${file_path}"))
    }
  ]

  dns_zone_files_by_name = {
    for source_file in local.dns_zone_files : source_file.zone.name => source_file...
  }

  dns_zones_duplicate = [
    for zone_name, source_files in local.dns_zone_files_by_name : zone_name
    if length(source_files) > 1
  ]
}

resource "terraform_data" "dns_validation" {
  input = sort(keys(local.dns_zone_files_by_name))

  lifecycle {
    precondition {
      condition     = length(local.dns_record_keys_duplicate) == 0
      error_message = "Manual DNS record identities must be unique per zone: ${join(", ", local.dns_record_keys_duplicate)}"
    }

    precondition {
      condition     = length(local.dns_zones_duplicate) == 0
      error_message = "DNS zone names must be unique: ${join(", ", local.dns_zones_duplicate)}"
    }

    precondition {
      condition     = length(local.dns_zone_file_names_mismatched) == 0
      error_message = "DNS YAML filenames must match their zone name: ${join(", ", local.dns_zone_file_names_mismatched)}"
    }

    precondition {
      condition     = length(local.dns_record_sets_conflicting_cname) == 0
      error_message = "DNS CNAME records cannot coexist with other records at the same name: ${join(", ", local.dns_record_sets_conflicting_cname)}"
    }
  }
}
