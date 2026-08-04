locals {
  _docker_servers = {
    for server_key, server in local.servers_model : server_key => server
    if server.features.docker
  }

  _docker_services = {
    for service_key, service in local.services_model : service_key => service
    if(
      can(local._docker_servers[service.target]) &&
      service.identity.service != null &&
      (service.target_feature == "" || service.target_feature == "docker")
    )
  }
}
