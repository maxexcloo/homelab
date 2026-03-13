locals {
  defaults = yamldecode(file("${path.module}/data/defaults.yml"))

  dns = {
    for filepath in fileset(path.module, "data/dns/*.yml") :
    yamldecode(file("${path.module}/${filepath}")).name => try(yamldecode(file("${path.module}/${filepath}")).records, [])
  }
}

output "summary" {
  description = "Summary of infrastructure managed by OpenTofu"
  sensitive   = false

  value = {
    counts = {
      dns_records = length(local.dns_records_acme_delegation) + length(local.dns_records_manual) + length(local.dns_records_servers) + length(local.dns_records_services) + length(local.dns_records_wildcards)
      servers     = length(local.servers)
      services    = length(local.services)
    }
    defaults = local.defaults
  }
}
