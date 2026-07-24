terraform {
  required_version = "~> 1.11"

  required_providers {
    htpasswd = {
      source = "loafoe/htpasswd"
    }

    random = {
      source = "hashicorp/random"
    }

    tls = {
      source = "hashicorp/tls"
    }
  }
}
