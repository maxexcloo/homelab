output "summary" {
  description = "Summary of infrastructure managed by OpenTofu"
  sensitive   = false

  value = {
    counts = {
      dns_records = length(local.dns_model_records_all)
      servers     = length(local.servers_model_desired)
      services    = length(local.services_model_desired)
    }

    servers  = keys(local.servers_model_desired)
    services = keys(local.services_model_desired)

    services_by_feature = {
      for feature, matches in local.services_outputs_by_feature : feature => keys(matches)
      if length(matches) > 0
    }
  }
}
