output "summary" {
  description = "Summary of infrastructure managed by OpenTofu"
  sensitive   = false

  value = {
    counts = {
      dns_records = (
        length(local.dns_records_acme_delegation) +
        length(local.dns_records_manual) +
        length(local.dns_records_servers) +
        length(local.dns_records_services) +
        length(local.dns_records_services_fly) +
        length(local.dns_records_services_urls) +
        length(local.dns_records_wildcards)
      )
      servers  = length(local.servers_model_desired)
      services = length(local.services_model_desired)
    }

    servers  = keys(local.servers_model_desired)
    services = keys(local.services_model_desired)

    services_by_feature = {
      for feature, matches in local.services_outputs_by_feature : feature => keys(matches)
      if length(matches) > 0
    }
  }
}
