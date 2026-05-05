locals {
  # Final DNS input map: zone name -> list of manually declared records.
  dns_input = {
    for dns_file in [
      for file_path in fileset(path.module, "data/dns/*.yml") :
      yamldecode(file("${path.module}/${file_path}"))
    ] : dns_file.name => try(dns_file.records, [])
  }

  # Managed Cloudflare zone names available for manual and generated records.
  dns_input_zones = keys(local.dns_input)
}
