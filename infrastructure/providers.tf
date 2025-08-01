terraform {
  required_version = ">= 1.6"

  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.8"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.17"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    # Configuration in backend.tf
  }
}

# Load provider configuration from 1Password
data "onepassword_item" "providers" {
  vault = "Infrastructure"
  title = "providers"
}

locals {
  providers = {
    for section in try(data.onepassword_item.providers.section, []) :
    section.label => {
      for field in section.field :
      field.label => field.value
    }
  }
}

# Configure providers
provider "onepassword" {
  service_account_token = local.providers.onepassword.service_account_token
}

provider "b2" {
  application_key    = local.providers.b2.application_key
  application_key_id = local.providers.b2.application_key_id
}

provider "cloudflare" {
  api_token = local.providers.cloudflare.api_token
}

provider "github" {
  token = local.providers.github.token
}

provider "oci" {
  fingerprint      = local.providers.oci.fingerprint
  private_key      = local.providers.oci.private_key
  region           = local.providers.oci.region
  tenancy_ocid     = local.providers.oci.tenancy_ocid
  user_ocid        = local.providers.oci.user_ocid
}

provider "tailscale" {
  api_key = local.providers.tailscale.api_key
}

# Proxmox providers will be configured dynamically per host