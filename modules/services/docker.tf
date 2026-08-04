removed {
  from = github_repository_file.docker_sops_config

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.encrypted_github_file_docker

  lifecycle {
    destroy = false
  }
}
