locals {
  _github_generated_repositories = {
    for repository_key, repository in local.defaults.github.deployment_repositories :
    repository_key => repository
    if repository_key != "fly"
  }

  _github_workflow_files = merge([
    for repository_key in keys(local._github_generated_repositories) : {
      for file_path in fileset(path.module, "templates/workflows/${repository_key}/**") : "${repository_key}/${trimprefix(file_path, "templates/workflows/${repository_key}/")}" => {
        file           = trimprefix(file_path, "templates/workflows/${repository_key}/")
        repository_key = repository_key
        source         = "${path.module}/${file_path}"
      }
      if contains([".json", ".py", ".yaml", ".yml"], try(regex("\\.[^.]+$", lower(file_path)), ""))
    }
  ]...)

  github_workflow_revisions = {
    for repository_key in keys(local._github_generated_repositories) : repository_key => sha256(jsonencode({
      for file_config in values(local._github_workflow_files) : file_config.file => filesha256(file_config.source)
      if file_config.repository_key == repository_key
    }))
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

resource "github_actions_variable" "catalog" {
  repository    = github_repository.deployment["fly"].name
  value         = jsonencode(module.services.catalog)
  variable_name = "HOMELAB_CATALOG"

  lifecycle {
    precondition {
      condition     = length(jsonencode(module.services.catalog)) <= 48000
      error_message = "The deployment catalog exceeds the safe GitHub Actions variable size."
    }

    precondition {
      error_message = "Every monitored service must have a 1Password item."

      condition = alltrue([
        for service in module.services.catalog.services : service.item != null
        if service.features.monitoring
      ])
    }
  }
}

resource "terraform_data" "catalog_deploy" {
  triggers_replace = [sha256(github_actions_variable.catalog.value)]

  provisioner "local-exec" {
    command = "gh workflow run deploy.yml --repo ${local.defaults.github.owner}/${github_repository.deployment["fly"].name} --ref main"
  }
}

resource "github_repository_file" "readme" {
  for_each = local._github_generated_repositories

  commit_message      = "Update README"
  content             = "# ${each.value.display_name} configuration\n\n${each.value.description}\n"
  file                = "README.md"
  overwrite_on_create = true
  repository          = github_repository.deployment[each.key].name

  lifecycle {
    destroy = false
  }
}

resource "github_repository_file" "renovate" {
  for_each = local._github_generated_repositories

  commit_message      = "Disable Renovate"
  file                = "renovate.json"
  overwrite_on_create = true
  repository          = github_repository.deployment[each.key].name

  content = jsonencode({
    enabled = false
  })

  lifecycle {
    destroy = false
  }
}

resource "github_repository_file" "workflow_file" {
  for_each = local._github_workflow_files

  commit_message      = "Update ${each.value.file}"
  content             = file(each.value.source)
  file                = each.value.file
  overwrite_on_create = true
  repository          = github_repository.deployment[each.value.repository_key].name

  lifecycle {
    destroy = false
  }
}
