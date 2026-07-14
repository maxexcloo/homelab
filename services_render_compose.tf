# Stage: render — Compose template inventory and rendered Compose files.
locals {
  # Compose template inventory selected only from model data and file existence.
  services_render_compose_inputs = {
    for service_key, service in local.services_model : service_key => {
      path = "${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl"
    }
    if(
      service.identity.service != null &&
      fileexists("${path.module}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl") &&
      (
        can(local.truenas_servers[service.target]) ||
        (
          can(local.servers_model[service.target]) &&
          local.servers_model[service.target].features.docker &&
          !(
            service.target_feature != "" &&
            local.servers_model[service.target].features.cloud_init
          )
        )
      )
    )
  }

  # Compose files with routing labels injected into the primary container's label map.
  services_render_write_compose = {
    for service_key, compose in {
      for service_key, compose_input in local.services_render_compose_inputs : service_key => yamldecode(
        templatefile(
          compose_input.path,
          local.services_render_template_context[service_key],
        ),
      )
      } : service_key => yamlencode(
      merge(
        compose,
        {
          services = {
            for compose_service_key, compose_service in compose.services : compose_service_key => merge(
              compose_service,
              try(length(local.services_render_services[service_key].routing_labels[compose_service_key]), 0) > 0 ? {
                labels = merge(
                  try(compose_service.labels, {}),
                  local.services_render_services[service_key].routing_labels[compose_service_key],
                )
              } : {},
            )
          }
        },
      )
    )
  }
}
