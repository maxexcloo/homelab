# username = "" resolves to the currently authenticated GitHub user.
data "github_user" "default" {
  username = ""
}

locals {
  github_repository_display_names = {
    docker  = "Docker"
    fly     = "Fly.io"
    truenas = "TrueNAS"
  }

  github_repository_descriptions = {
    for repository_key, repository_name in local.defaults.github.repositories :
    repository_key => "${local.github_repository_display_names[repository_key]} services configuration (SOPS-encrypted), generated and managed by the homelab OpenTofu repository."
  }

  github_repository_readmes = {
    for repository_key, repository_description in local.github_repository_descriptions :
    repository_key => "# ${local.github_repository_display_names[repository_key]} configuration\n\n${repository_description}\n"
  }

  github_workflow_files = merge([
    for repository_key, repository_name in local.defaults.github.repositories : {
      for file_path in fileset(path.module, "templates/workflows/${repository_key}/**") : "${repository_key}/${trimprefix(file_path, "templates/workflows/${repository_key}/")}" => {
        file           = trimprefix(file_path, "templates/workflows/${repository_key}/")
        repository_key = repository_key
        source         = "${path.module}/${file_path}"
      }
      if contains([".py", ".yml", ".yaml"], try(regex("\\.[^.]+$", lower(file_path)), ""))
    }
  ]...)

  github_workflow_revisions = {
    for repository_key in keys(local.defaults.github.repositories) : repository_key => sha256(jsonencode({
      for file_config in values(local.github_workflow_files) : file_config.file => filesha256(file_config.source)
      if file_config.repository_key == repository_key
    }))
  }
}

resource "github_repository" "deployment" {
  for_each = local.defaults.github.repositories

  delete_branch_on_merge = true
  description            = local.github_repository_descriptions[each.key]
  name                   = each.value
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
  for_each = local.github_repository_readmes

  commit_message      = "Update README"
  content             = each.value
  file                = "README.md"
  overwrite_on_create = true
  repository          = github_repository.deployment[each.key].name
}

resource "github_repository_file" "workflow_file" {
  for_each = local.github_workflow_files

  commit_message      = "Update ${each.value.file}"
  content             = file(each.value.source)
  file                = each.value.file
  overwrite_on_create = true
  repository          = github_repository.deployment[each.value.repository_key].name
}
