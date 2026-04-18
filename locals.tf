locals {
  _defaults = yamldecode(file("${path.module}/data/defaults.yml"))

  _dns = {
    for filepath in fileset(path.module, "data/dns/*.yml") :
    filepath => yamldecode(file("${path.module}/${filepath}"))
  }

  defaults = {
    for k, v in local._defaults : k => v
    if !contains(["dns", "servers", "services"], k)
  }

  dns = {
    for filepath, data in local._dns :
    data.name => try(data.records, [])
  }

  dns_defaults = local._defaults.dns

  server_defaults = local._defaults.servers

  service_defaults = local._defaults.services

  sops_encrypt_script = file("${path.module}/templates/scripts/sops_encrypt.sh")
}

output "summary" {
  description = "Summary of infrastructure managed by OpenTofu"
  sensitive   = false

  value = {
    counts = {
      dns_records = length(local.dns_records_acme_delegation) + length(local.dns_records_manual) + length(local.dns_records_servers) + length(local.dns_records_services) + length(local.dns_records_services_fly) + length(local.dns_records_services_urls) + length(local.dns_records_wildcards)
      servers     = length(local.servers)
      services    = length(local.services)
    }

    defaults = local.defaults
    servers  = keys(local.servers)
    services = keys(local.services)

    services_by_feature = {
      for feature, matches in local.services_by_feature : feature => keys(matches)
      if length(matches) > 0
    }
  }
}
