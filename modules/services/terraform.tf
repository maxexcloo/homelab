terraform {
  required_version = "~> 1.11"

  required_providers {
    age = {
      source = "clementblaise/age"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
    deepmerge = {
      source = "isometry/deepmerge"
    }
    github = {
      source = "integrations/github"
    }
    http = {
      source = "hashicorp/http"
    }
    pocketid = {
      source = "trozz/pocketid"
    }
    restapi = {
      source = "mastercard/restapi"

      configuration_aliases = [
        restapi.onepassword,
        restapi.resend,
      ]
    }
    shell = {
      source = "linyinfeng/shell"
    }
  }
}
