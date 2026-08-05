locals {
  _github_config_values = {
    for repository_key, config in local._github_configs :
    repository_key => repository_key == "truenas" ? base64gzip(jsonencode(config)) : jsonencode(config)
  }

  _github_configs = module.services.configs

  _github_fly_deployments = {
    for deployment in local._github_configs.fly.deployments : deployment.key => {
      app        = deployment.app
      owner      = local.defaults.github.owner
      repository = local.defaults.github.deployment_repositories.fly.name
    }
  }

  _github_truenas_deployments = {
    for deployment in local._github_configs.truenas.deployments : deployment.key => {
      name       = deployment.name
      owner      = local.defaults.github.owner
      repository = local.defaults.github.deployment_repositories.truenas.name
      target     = deployment.target
    }
  }

}

resource "github_repository" "deployment" {
  for_each = local.defaults.github.deployment_repositories

  delete_branch_on_merge = true
  description            = each.value.description
  name                   = each.value.name
  visibility             = each.value.visibility

  lifecycle {
    ignore_changes = [
      has_downloads,
      ignore_vulnerability_alerts_during_read,
    ]
  }
}

resource "github_actions_variable" "config" {
  for_each = local._github_configs

  repository    = github_repository.deployment[each.key].name
  value         = local._github_config_values[each.key]
  variable_name = "CONFIG"

  lifecycle {
    precondition {
      condition     = length(local._github_config_values[each.key]) <= 48000
      error_message = "The ${each.key} deployment config exceeds the safe GitHub Actions variable size."
    }

    precondition {
      error_message = "Every service in the ${each.key} deployment config must have a 1Password item."

      condition = each.key != "fly" || alltrue([
        for service in each.value.services : service.item != null
      ])
    }
  }
}

resource "terraform_data" "config_deploy" {
  for_each = local._github_configs

  triggers_replace = [sha256(github_actions_variable.config[each.key].value)]

  provisioner "local-exec" {
    command = "gh workflow run ${each.value.workflow} --repo ${local.defaults.github.owner}/${github_repository.deployment[each.key].name} --ref main"
  }
}

resource "terraform_data" "fly_deployment" {
  for_each = local._github_fly_deployments

  input            = each.value
  triggers_replace = [each.value.app]

  provisioner "local-exec" {
    command = "gh workflow run deploy.yaml --repo ${self.input.owner}/${self.input.repository} --ref main -f action=delete -f deployment=${self.input.app}"
    when    = destroy
  }
}

resource "terraform_data" "truenas_deployment" {
  for_each = local._github_truenas_deployments

  input            = each.value
  triggers_replace = [each.value.name]

  provisioner "local-exec" {
    command = "gh workflow run deploy.yaml --repo ${self.input.owner}/${self.input.repository} --ref main -f action=delete -f deployment=${self.input.target}/${self.input.name}"
    when    = destroy
  }
}
