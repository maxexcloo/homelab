# username = "" resolves to the currently authenticated GitHub user.
data "github_user" "default" {
  username = ""
}

locals {
  _github_config_deployments = merge([
    for repository_key, config in local.services_configs : {
      for dispatch_key, dispatch in try(local.services_config_workflow_dispatches[repository_key], {
        (repository_key) = {
          fingerprint = sha256(local._github_config_values[repository_key])
          inputs      = {}
        }
        }) : dispatch_key => {
        fingerprint = dispatch.fingerprint
        inputs      = dispatch.inputs
        owner       = local.defaults.github.owner
        repository  = local.defaults.github.deployment_repositories[repository_key].name
        workflow    = config.workflow
      }
    }
  ]...)

  _github_config_values = {
    for repository_key, config in local.services_configs :
    repository_key => repository_key == "truenas" ? base64gzip(jsonencode(config)) : jsonencode(config)
  }

  _github_fly_deployments = {
    for deployment in local.services_configs.fly.deployments : deployment.key => {
      app        = deployment.app
      owner      = local.defaults.github.owner
      repository = local.defaults.github.deployment_repositories.fly.name
    }
  }

  _github_truenas_deployments = {
    for deployment in local.services_configs.truenas.deployments : deployment.key => {
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
  for_each = local.services_configs

  repository    = github_repository.deployment[each.key].name
  value         = local._github_config_values[each.key]
  variable_name = "CONFIG"

  lifecycle {
    precondition {
      condition     = length(local._github_config_values[each.key]) <= 48000
      error_message = "The ${each.key} deployment config exceeds the safe GitHub Actions variable size."
    }
  }
}

resource "terraform_data" "config_deployment" {
  for_each = local._github_config_deployments

  input            = each.value
  triggers_replace = [each.value.fingerprint]

  depends_on = [
    github_actions_variable.config,
    terraform_data.server_onepassword,
    terraform_data.service_onepassword,
  ]

  provisioner "local-exec" {
    command = join(" ", concat(
      [
        "gh",
        "workflow",
        "run",
        self.input.workflow,
        "--repo",
        "${self.input.owner}/${self.input.repository}",
        "--ref",
        "main",
      ],
      flatten([
        for input_key, input_value in self.input.inputs : [
          "--field",
          "${input_key}=${input_value}",
        ]
      ]),
    ))
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
