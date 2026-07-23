locals {
  dns_input = {
    for zone_name, zone_files in local.dns_input_source_files_by_zone :
    zone_name => try(zone_files[0].zone.records, [])
  }

  dns_input_source_files = [
    for file_path in fileset(path.module, "data/dns/*.yml") : {
      file_key = trimsuffix(basename(file_path), ".yml")
      zone     = yamldecode(file("${path.module}/${file_path}"))
    }
  ]

  dns_input_source_files_by_zone = {
    for dns_file in local.dns_input_source_files : dns_file.zone.name => dns_file...
  }
}
