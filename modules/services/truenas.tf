locals {
  truenas_servers = {
    for server_key, server in local.servers_model : server_key => server
    if server.platform == "truenas"
  }

  truenas_services = {
    for service_key, service in local.services_model : service_key => service
    if(
      service.identity.service != null &&
      can(local.truenas_servers[service.target])
    )
  }
}

removed {
  from = github_repository_file.truenas_sops_config

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.encrypted_github_file_truenas

  lifecycle {
    destroy = false
  }
}

removed {
  from = github_repository_file.truenas_deploy_request

  lifecycle {
    destroy = false
  }
}
