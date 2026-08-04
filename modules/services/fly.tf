# Fly deploys share one repository key because app files are isolated by app
# directory in the deploy repository.
resource "github_actions_secret" "fly_age_key" {
  repository  = var.integrations.github.repositories.fly
  secret_name = "AGE_KEY"
  value       = age_secret_key.fly.secret_key
}

removed {
  from = github_repository_file.fly_deploy_request

  lifecycle {
    destroy = false
  }
}

removed {
  from = github_repository_file.fly_sops_config

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.encrypted_github_file_fly

  lifecycle {
    destroy = false
  }
}
