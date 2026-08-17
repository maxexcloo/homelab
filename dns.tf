locals {
  dns_all_records = merge(local.dns_derived_records, local.dns_manual_records)

  dns_conflicting_cnames = [
    for record_set, records in local.dns_record_sets : record_set
    if contains([for record in records : record.type], "CNAME") && length(records) > 1
  ]

  dns_duplicate_record_keys = [
    for record_key, entries in local.dns_manual_entries_by_key : record_key
    if length(entries) > 1
  ]

  dns_duplicate_zones = [
    for zone_name, source_files in local.dns_source_files_by_zone : zone_name
    if length(source_files) > 1
  ]

  dns_file_name_mismatches = [
    for source_file in local.dns_source_files :
    "${source_file.file_name} -> ${source_file.zone.name}"
    if source_file.file_name != source_file.zone.name
  ]

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
        name     = "api.${cluster_name}.${local.domains.domains.services}"
        priority = null
        proxied  = false
        ttl      = 300
        type     = "A"
        zone     = local.domains.domains.services
      }
    },
    {
      for cluster_name, cluster in local.clusters : "cluster/${cluster_name}/tailscale" => {
        comment  = "Managed by OpenTofu"
        content  = local.tailscale_device_ipv4[cluster_name]
        name     = "*.${cluster_name}.${local.domains.domains.services}"
        priority = null
        proxied  = false
        ttl      = 300
        type     = "A"
        zone     = local.domains.domains.services
      }
      if try(local.tailscale_device_ipv4[cluster_name], null) != null
    },
    {
      for cluster_name, cluster in local.clusters : "cluster/${cluster_name}/tailscale-aaaa" => {
        comment  = "Managed by OpenTofu"
        content  = local.tailscale_device_ipv6[cluster_name]
        name     = "*.${cluster_name}.${local.domains.domains.services}"
        priority = null
        proxied  = false
        ttl      = 300
        type     = "AAAA"
        zone     = local.domains.domains.services
      }
      if try(local.tailscale_device_ipv6[cluster_name], null) != null
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
        zone     = consumer.challenge_zone
      }
    },
  )

  dns_manual_entries = flatten([
    for source_file in local.dns_source_files : [
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

  dns_manual_entries_by_key = {
    for entry in local.dns_manual_entries :
    "${entry.zone}-manual-${entry.key}" => entry...
  }

  dns_manual_records = {
    for record_key, entries in local.dns_manual_entries_by_key : record_key => {
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

  dns_record_sets = {
    for record in values(local.dns_all_records) :
    "${record.zone}/${record.name}" => record...
  }

  dns_source_files = [
    for file_path in fileset(path.module, "data/dns/*.yaml") : {
      file_name = trimsuffix(basename(file_path), ".yaml")
      zone      = yamldecode(file("${path.module}/${file_path}"))
    }
  ]

  dns_source_files_by_zone = {
    for source_file in local.dns_source_files : source_file.zone.name => source_file...
  }
}

resource "terraform_data" "dns_validation" {
  input = sort(keys(local.dns_source_files_by_zone))

  lifecycle {
    precondition {
      condition     = length(local.dns_duplicate_record_keys) == 0
      error_message = "Manual DNS record identities must be unique per zone: ${join(", ", local.dns_duplicate_record_keys)}"
    }

    precondition {
      condition     = length(local.dns_duplicate_zones) == 0
      error_message = "DNS zone names must be unique: ${join(", ", local.dns_duplicate_zones)}"
    }

    precondition {
      condition     = length(local.dns_file_name_mismatches) == 0
      error_message = "DNS YAML filenames must match their zone name: ${join(", ", local.dns_file_name_mismatches)}"
    }

    precondition {
      condition     = length(local.dns_conflicting_cnames) == 0
      error_message = "DNS CNAME records cannot coexist with other records at the same name: ${join(", ", local.dns_conflicting_cnames)}"
    }
  }
}
