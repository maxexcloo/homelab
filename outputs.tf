output "summary" {
  description = "Summary of infrastructure managed by OpenTofu"
  sensitive   = false

  value = {
    counts = {
      dns_records = length(local.dns_model_records_all)
      servers     = length(local.servers_model)
      services    = length(local.services_model)
    }

    servers  = keys(local.servers_model)
    services = keys(local.services_model)

    services_by_feature = {
      for feature, matches in local.services_by_feature : feature => keys(matches)
      if length(matches) > 0
    }
  }
}
