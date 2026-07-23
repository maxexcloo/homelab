# Stage: render — generic Compose template inventory and decoded files.
locals {
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
