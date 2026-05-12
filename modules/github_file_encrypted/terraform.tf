terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    shell = {
      source  = "linyinfeng/shell"
      version = "~> 1.0"
    }
  }
}
