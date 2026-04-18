terraform {
  required_version = "~> 1.10"

  required_providers {
    age = {
      source  = "clementblaise/age"
      version = ">= 0.1, < 1.0"
    }
    b2 = {
      source  = "backblaze/b2"
      version = ">= 0.12, < 1.0"
    }
    bcrypt = {
      source  = "viktorradnai/bcrypt"
      version = ">= 0.1, < 1.0"
    }
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = ">= 0.17, < 1.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    deepmerge = {
      source  = "isometry/deepmerge"
      version = ">= 1.0, < 2.0, != 1.2.2"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    restapi = {
      source  = "mastercard/restapi"
      version = "~> 3.0"
    }
    shell = {
      source  = "linyinfeng/shell"
      version = "~> 1.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = ">= 0.28, < 1.0"
    }
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = ">= 0.41, < 1.0"
    }
  }
}
