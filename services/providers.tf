terraform {
  required_version = ">= 1.6"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    fly = {
      source  = "fly-apps/fly"
      version = "~> 0.1"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure providers using 1Password
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

# Cloudflare provider
provider "cloudflare" {
  api_token = try(local.providers.cloudflare.api_token, "")
}

# Fly.io provider
provider "fly" {
  fly_api_token = try(local.providers.fly.api_token, "")
}

# 1Password provider
provider "onepassword" {
  # Uses OP_SERVICE_ACCOUNT_TOKEN environment variable
}

# Random provider
provider "random" {}
