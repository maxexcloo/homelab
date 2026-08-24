language {
  compatible_with {
    opentofu = ">= 1.12"
  }
}

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.23.0"
    }

    deepmerge = {
      source  = "isometry/deepmerge"
      version = "1.3.0"
    }

    oci = {
      source  = "oracle/oci"
      version = "8.28.0"
    }

    onepassword = {
      source  = "1Password/onepassword"
      version = "3.3.1"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }

    truenas = {
      source  = "PjSalty/truenas"
      version = "2.4.1"
    }

    unifi = {
      source  = "ubiquiti-community/unifi"
      version = "0.55.0"
    }
  }
}
