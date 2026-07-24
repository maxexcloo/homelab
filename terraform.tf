terraform {
  required_version = "~> 1.11"

  required_providers {
    age = {
      source  = "clementblaise/age"
      version = "~> 0.1"
    }

    b2 = {
      source  = "backblaze/b2"
      version = "~> 0.13"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.22"
    }

    deepmerge = {
      source  = "isometry/deepmerge"
      version = ">= 1.0, < 2.0, != 1.2.2"
    }

    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }

    htpasswd = {
      source  = "loafoe/htpasswd"
      version = "2.1.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
    }

    incus = {
      source  = "lxc/incus"
      version = "~> 1.1"
    }

    oci = {
      source  = "oracle/oci"
      version = "~> 8.24"
    }

    pocketid = {
      source  = "trozz/pocketid"
      version = "2.3.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
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
      version = "~> 0.29"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.3"
    }

    unifi = {
      source  = "ubiquiti-community/unifi"
      version = "~> 0.55"
    }
  }
}
