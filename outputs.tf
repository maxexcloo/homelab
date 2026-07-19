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

    services_by_feature = merge(
      {
        for feature, matches in local.services_model_by_feature : feature => keys(matches)
        if(
          !contains(["monitoring", "monitoring_alerts"], feature) &&
          length(matches) > 0
        )
      },
      {
        monitoring_alerts_disabled = [
          for service_key in keys(local.services_model) : service_key
          if !local.services_model[service_key].features.monitoring_alerts
        ]
        monitoring_disabled = [
          for service_key in keys(local.services_model) : service_key
          if !local.services_model[service_key].features.monitoring
        ]
      },
    )
  }
}
