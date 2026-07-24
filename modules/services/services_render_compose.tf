# Stage: render — generic Compose template inventory and decoded files.
locals {
  # Final Compose files with Traefik labels injected into container label maps.
  services_render_compose = {
    for service_key, compose in local.services_render_compose_base : service_key => yamlencode(
      merge(
        compose,
        {
          services = {
            for compose_service_key, compose_service in compose.services : compose_service_key => merge(
              compose_service,
              try(length(local._services_render_traefik_routing_labels[service_key][compose_service_key]), 0) > 0 ? {
                labels = merge(
                  try(compose_service.labels, {}),
                  {
                    for label_key, label_value in local._services_render_traefik_routing_labels[service_key][compose_service_key] :
                    # TrueNAS escapes Compose interpolation itself; direct Docker Compose does not.
                    label_key => can(local.truenas_servers[local.services_model[service_key].target]) ? label_value : replace(label_value, "$", "$$")
                    if label_value != null
                  },
                )
              } : {},
            )
          }
        },
      )
    )
  }

  services_render_compose_base = {
    for service_key, compose_input in local.services_render_compose_inputs : service_key => yamldecode(
      templatefile(
        compose_input.path,
        local.services_render_template_context[service_key],
      )
    )
  }

  # Compose template inventory selected only from model data and file existence.
  # Docker-fleet stacks stay under doco-cd on bootstrapped hosts; other
  # auto-expanded services are bootstrap-managed there.
  services_render_compose_inputs = {
    for service_key, service in local.services_model : service_key => {
      path = "${path.root}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl"
    }
    if(
      service.identity.service != null &&
      fileexists("${path.root}/templates/services/${service.identity.service}/docker-compose.yaml.tftpl") &&
      (
        can(local.truenas_servers[service.target]) ||
        (
          can(local.servers_model[service.target]) &&
          local.servers_model[service.target].features.docker &&
          !(
            local.servers_model[service.target].features.bootstrap &&
            service.target_feature != "" &&
            service.target_feature != "docker"
          )
        )
      )
    )
  }
}
