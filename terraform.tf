terraform {
  required_version = ">= 1.10"

  required_providers {
    age = {
      source  = "clementblaise/age"
      version = "~> 0.0"
    }
    b2 = {
      source  = "backblaze/b2"
      version = "~> 0.0"
    }
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = ">= 0.17.3"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    htpasswd = {
      source  = "loafoe/htpasswd"
      version = "~> 1.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    incus = {
      source = "lxc/incus"
      version = "1.0.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    restapi = {
      source  = "mastercard/restapi"
      version = "~> 2.0"
    }
    shell = {
      source  = "linyinfeng/shell"
      version = "~> 1.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.0"
    }
    unifi = {
      source = "ubiquiti-community/unifi"
      version = "0.41.17"
    }
  }
}
