output "summary" {
  description = "Summary of infrastructure managed by OpenTofu"
  sensitive   = false

  value = {
    servers  = keys(local.servers_model)
    services = keys(local.services_model)

    counts = {
      dns_records = length(local.dns_render_records)
      servers     = length(local.servers_model)
      services    = length(local.services_model)
    }

    services_by_feature = {
      for feature, matches in local.services_by_feature : feature => keys(matches)
      if length(matches) > 0
    }
  }
}
