language {
  compatible_with {
    opentofu = ">= 1.12"
  }
}

terraform {
  required_providers {
    b2 = {
      source  = "backblaze/b2"
      version = "0.14.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.25.0"
    }

    deepmerge = {
      source  = "isometry/deepmerge"
      version = "1.3.1"
    }

    oci = {
      source  = "oracle/oci"
      version = "9.2.0"
    }

    onepassword = {
      source  = "1Password/onepassword"
      version = "3.3.1"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }

    resend = {
      source  = "y0n0zawa/resend"
      version = "1.0.1"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0"
    }

    truenas = {
      source  = "PjSalty/truenas"
      version = "3.0.0"
    }

    unifi = {
      source  = "ubiquiti-community/unifi"
      version = "0.55.0"
    }
  }
}
