# username = "" resolves to the currently authenticated GitHub user.
data "github_user" "default" {
  username = ""
}

locals {
  github_workflow_files = merge([
    for repository_key, repository_name in local.defaults.github.repositories : {
      for file_path in fileset(path.module, "templates/workflows/${repository_key}/**") : "${repository_key}/${trimprefix(file_path, "templates/workflows/${repository_key}/")}" => {
        file       = trimprefix(file_path, "templates/workflows/${repository_key}/")
        repository = repository_name
        source     = "${path.module}/${file_path}"
      }
      if contains([".py", ".yml", ".yaml"], try(regex("\\.[^.]+$", lower(file_path)), ""))
    }
  ]...)

  github_workflow_revisions = {
    for repository_key in keys(local.defaults.github.repositories) : repository_key => sha256(jsonencode({
      for file_config in values(local.github_workflow_files) : file_config.file => filesha256(file_config.source)
      if file_config.repository == local.defaults.github.repositories[repository_key]
    }))
  }
}

resource "github_repository_file" "workflow_file" {
  for_each = local.github_workflow_files

  commit_message      = "Update ${each.value.file}"
  content             = file(each.value.source)
  file                = each.value.file
  overwrite_on_create = true
  repository          = each.value.repository
}
