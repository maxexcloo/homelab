terraform {
  required_version = "~> 1.11"

  required_providers {
    b2 = {
      source = "backblaze/b2"
    }

    random = {
      source = "hashicorp/random"
    }
  }
}
