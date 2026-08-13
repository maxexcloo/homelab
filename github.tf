# username = "" resolves to the currently authenticated GitHub user.
data "github_user" "default" {
  username = ""
}

locals {
  _github_config_deployments = merge([
    for repository_key, config in local._github_configs : {
      for dispatch_key, dispatch in local._github_config_dispatches[repository_key] : dispatch_key => {
        fingerprint = dispatch.fingerprint
        inputs      = dispatch.inputs
        owner       = local.defaults.github.owner
        repository  = local.defaults.github.deployment_repositories[repository_key].name
        workflow    = config.workflow
      }
    }
  ]...)

  _github_config_dispatches = merge(
    {
      for repository_key in keys(local._github_configs) : repository_key => {
        (repository_key) = {
          fingerprint = sha256(local._github_config_values[repository_key])
          inputs      = {}
        }
      }
    },
    local._github_config_workflow_dispatches,
  )

  _github_config_values = {
    for repository_key, config in local._github_configs :
    repository_key => repository_key == "truenas" ? base64gzip(jsonencode(config)) : jsonencode(config)
  }

  _github_config_workflow_dispatches = {
    truenas = {
      for target_key in toset([
        for service_key in keys(local._services_config_truenas_deployments) :
        local.services_model[service_key].target
        ]) : "truenas/${target_key}" => {
        fingerprint = sha256(jsonencode([
          for service_key, deployment in local._services_config_truenas_deployments :
          deployment
          if local.services_model[service_key].target == target_key
        ]))

        inputs = {
          changed_only = true
          deployment   = target_key
        }
      }
    }
  }

  _github_configs = {
    docker  = local.services_config_docker
    fly     = local.services_config_fly
    truenas = local.services_config_truenas
  }

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
  }
}

resource "terraform_data" "config_deployment" {
  for_each = local._github_config_deployments

  input            = each.value
  triggers_replace = [sha256(jsonencode(each.value))]

  depends_on = [
    github_actions_variable.config,
    terraform_data.onepassword_cleanup,
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
