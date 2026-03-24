locals {
  _defaults        = yamldecode(file("${path.module}/data/defaults.yml"))
  dns_defaults     = local._defaults.dns
  server_defaults  = local._defaults.servers
  service_defaults = local._defaults.services

  defaults = {
    for k, v in local._defaults : k => v
    if !contains(["dns", "servers", "services"], k)
  }

  dns = {
    for filepath in fileset(path.module, "data/dns/*.yml") :
    yamldecode(file("${path.module}/${filepath}")).name => try(yamldecode(file("${path.module}/${filepath}")).records, [])
  }
}

output "summary" {
  description = "Summary of infrastructure managed by OpenTofu"
  sensitive   = false

  value = {
    defaults = local.defaults
    servers  = keys(local.servers)
    services = keys(local.services)

    counts = {
      dns_records = length(local.dns_records_acme_delegation) + length(local.dns_records_manual) + length(local.dns_records_servers) + length(local.dns_records_services) + length(local.dns_records_services_urls) + length(local.dns_records_wildcards)
      servers     = length(local.servers)
      services    = length(local.services)
    }
  }
}
