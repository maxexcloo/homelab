locals {
  _docker_servers = {
    for server_key, server in local.servers_model : server_key => server
    if server.features.docker
  }

  _docker_services = {
    for service_key, service in local.services_model : service_key => service
    if(
      can(local._docker_servers[service.target]) &&
      can(local.services_render_compose_inputs[service_key])
    )
  }
}
