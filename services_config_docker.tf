# Stage: config — Docker deployment context.
locals {
  services_config_docker = {
    repository = "docker"
    workflow   = "publish.yaml"

    deployments = [
      for service_key, service in local.services_model : merge(
        local.services_config_deployments[service_key],
        {
          routing_labels = {
            for container, labels in local.services_config_deployments[service_key].routing_labels : container => {
              for label_key, label_value in labels : label_key => replace(
                label_value,
                "op://${local.defaults.onepassword.vaults.services.id}/${local.onepassword_service_item_ids[service_key]}/monitoring_token",
                "$${MONITORING_TOKEN}",
              )
            }
          }
        },
      )
      if(
        can(local.servers_model_by_feature.docker[service.target]) &&
        service.identity.service != null &&
        (service.target_feature == "" || service.target_feature == "docker")
      )
    ]

    targets = [
      for server_key in keys(local.servers_model_by_feature.docker) : {
        key = server_key
      }
    ]
  }
}
