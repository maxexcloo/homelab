terraform {
  required_version = "~> 1.11"

  required_providers {
    age = {
      source  = "clementblaise/age"
      version = "~> 0.1"
    }
    b2 = {
      source  = "backblaze/b2"
      version = "~> 0.12"
    }
    bcrypt = {
      source  = "viktorradnai/bcrypt"
      version = "~> 0.1"
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
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 8.23"
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
      version = "~> 1.7"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.28"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = "~> 0.41"
    }
  }
}
