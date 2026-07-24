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

    incus = {
      source = "lxc/incus"
    }

    oci = {
      source = "oracle/oci"
    }

    restapi = {
      source = "mastercard/restapi"

      configuration_aliases = [
        restapi.onepassword,
        restapi.resend,
      ]
    }

    unifi = {
      source = "ubiquiti-community/unifi"
    }
  }
}
