locals {
  dns_records = merge(local.dns_records_derived, local.dns_records_manual)

  dns_record_entries_manual = flatten([
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
  ])

  dns_record_entries_manual_by_key = {
    for entry in local.dns_record_entries_manual :
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

  dns_records_derived = merge(
    {
      for name, machine in local.machines : "machine/${name}/a" => {
        comment  = "Managed by OpenTofu"
        content  = try(machine.public_ipv4, machine.address)
        name     = local.machine_fqdns[name]
        priority = null
        proxied  = false
        ttl      = 300
        type     = "A"
        zone     = local.domains.infrastructure
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
        zone     = local.domains.infrastructure
      }
      if try(machine.public_ipv6, null) != null
    },
    {
      for cluster_name, cluster in local.clusters : "cluster/${cluster_name}/api" => {
        comment  = "Managed by OpenTofu"
        content  = local.machines[cluster.api_node].address
        name     = "api.${cluster_name}.${local.domains.services}"
        priority = null
        proxied  = false
        ttl      = 300
        type     = "A"
        zone     = local.domains.services
      }
    },
    {
      for cluster_name, cluster in local.clusters : "cluster/${cluster_name}/tailscale" => {
        comment  = "Managed by OpenTofu"
        content  = local.tailscale_device_ipv4[cluster_name]
        name     = "*.${cluster_name}.${local.domains.services}"
        priority = null
        proxied  = false
        ttl      = 300
        type     = "A"
        zone     = local.domains.services
      }
      if try(local.tailscale_device_ipv4[cluster_name], null) != null
    },
    {
      for cluster_name, cluster in local.clusters : "cluster/${cluster_name}/tailscale-aaaa" => {
        comment  = "Managed by OpenTofu"
        content  = local.tailscale_device_ipv6[cluster_name]
        name     = "*.${cluster_name}.${local.domains.services}"
        priority = null
        proxied  = false
        ttl      = 300
        type     = "AAAA"
        zone     = local.domains.services
      }
      if try(local.tailscale_device_ipv6[cluster_name], null) != null
    },
    {
      for name, consumer in local.cloudflare_consumers_acme : "acme/${name}" => {
        comment  = "Managed by OpenTofu"
        content  = consumer.target_hostname
        name     = "_acme-challenge.${consumer.challenge_hostname}"
        priority = null
        proxied  = false
        ttl      = 300
        type     = "CNAME"
        zone     = consumer.challenge_zone
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
