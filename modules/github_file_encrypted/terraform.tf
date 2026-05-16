terraform {
  required_version = "~> 1.11"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.12"
    }
    shell = {
      source  = "linyinfeng/shell"
      version = "~> 1.7"
    }
  }
}
