terraform {
  required_version = "~> 1.11"

  required_providers {
    http = {
      source = "hashicorp/http"
    }

    restapi = {
      source = "mastercard/restapi"
    }
  }
}
