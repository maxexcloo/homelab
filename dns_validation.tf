locals {
  _dns_validation_duplicate_record_keys = [
    for record_key, entries in local.dns_model_manual_entries_by_key : record_key
    if length(entries) > 1
  ]

  _dns_validation_duplicate_zones = [
    for zone_name, zone_files in local.dns_input_source_files_by_zone : zone_name
    if length(zone_files) > 1
  ]

  _dns_validation_file_key_mismatches = [
    for dns_file in local.dns_input_source_files : "${dns_file.file_key} -> ${dns_file.zone.name}"
    if dns_file.file_key != dns_file.zone.name
  ]
}

resource "terraform_data" "dns_validation" {
  input = keys(local.dns_input)

  lifecycle {
    precondition {
      condition     = length(local._dns_validation_duplicate_record_keys) == 0
      error_message = "Manual DNS record identities must be unique per zone: ${join(", ", local._dns_validation_duplicate_record_keys)}"
    }

    precondition {
      condition     = length(local._dns_validation_duplicate_zones) == 0
      error_message = "DNS zone names must be unique: ${join(", ", local._dns_validation_duplicate_zones)}"
    }

    precondition {
      condition     = length(local._dns_validation_file_key_mismatches) == 0
      error_message = "DNS YAML filenames must match the zone name: ${join(", ", local._dns_validation_file_key_mismatches)}"
    }
  }
}
