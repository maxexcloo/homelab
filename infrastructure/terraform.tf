terraform {
  required_version = ">= 1.10"

  required_providers {
    b2 = {
      source  = "backblaze/b2"
      version = "~> 0.10"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
    onepassword = {
      source  = "1password/onepassword"
      version = "~> 2.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.81"
    }
    restapi = {
      source  = "mastercard/restapi"
      version = "~> 2.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.21"
    }
  }
}
