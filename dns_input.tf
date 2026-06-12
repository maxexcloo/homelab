locals {
  _dns_input_files = [
    for file_path in fileset(path.module, "data/dns/*.yml") : {
      file_key = trimsuffix(basename(file_path), ".yml")
      zone     = yamldecode(file("${path.module}/${file_path}"))
    }
  ]

  _dns_input_files_by_zone = {
    for dns_file in local._dns_input_files : dns_file.zone.name => dns_file...
  }

  # Final DNS input map: zone name -> list of manually declared records.
  dns_input = {
    for zone_name, zone_files in local._dns_input_files_by_zone :
    zone_name => try(zone_files[0].zone.records, [])
  }
}
