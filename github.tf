# username = "" resolves to the currently authenticated GitHub user.
data "github_user" "default" {
  username = ""
}

locals {
  _github_workflow_files = merge([
    for repository_key in keys(local.defaults.github.deployment_repositories) : {
      for file_path in fileset(path.module, "templates/workflows/${repository_key}/**") : "${repository_key}/${trimprefix(file_path, "templates/workflows/${repository_key}/")}" => {
        file           = trimprefix(file_path, "templates/workflows/${repository_key}/")
        repository_key = repository_key
        source         = "${path.module}/${file_path}"
      }
      if contains([".py", ".yml", ".yaml"], try(regex("\\.[^.]+$", lower(file_path)), ""))
    }
  ]...)

  github_workflow_revisions = {
    for repository_key in keys(local.defaults.github.deployment_repositories) : repository_key => sha256(jsonencode({
      for file_config in values(local._github_workflow_files) : file_config.file => filesha256(file_config.source)
      if file_config.repository_key == repository_key
    }))
  }
}

import {
  id = "docker"
  to = github_repository.deployment["docker"]
}

import {
  id = "fly"
  to = github_repository.deployment["fly"]
}

import {
  id = "truenas"
  to = github_repository.deployment["truenas"]
}

resource "github_repository" "deployment" {
  for_each = local.defaults.github.deployment_repositories

  delete_branch_on_merge = true
  description            = each.value.description
  name                   = each.value.name
  visibility             = "public"

  lifecycle {
    ignore_changes = [
      has_downloads,
      ignore_vulnerability_alerts_during_read,
    ]
    prevent_destroy = true
  }
}

resource "github_repository_file" "readme" {
  for_each = local.defaults.github.deployment_repositories

  commit_message      = "Update README"
  content             = "# ${each.value.display_name} configuration\n\n${each.value.description}\n"
  file                = "README.md"
  overwrite_on_create = true
  repository          = github_repository.deployment[each.key].name
}

resource "github_repository_file" "workflow_file" {
  for_each = local._github_workflow_files

  commit_message      = "Update ${each.value.file}"
  content             = file(each.value.source)
  file                = each.value.file
  overwrite_on_create = true
  repository          = github_repository.deployment[each.value.repository_key].name
}
