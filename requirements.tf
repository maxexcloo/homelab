language {
  compatible_with {
    opentofu = ">= 1.12"
  }
}

terraform {
  required_providers {
    b2 = {
      source = "backblaze/b2"
    }

    cloudflare = {
      source = "cloudflare/cloudflare"
    }

    deepmerge = {
      source = "isometry/deepmerge"
    }

    oci = {
      source = "oracle/oci"
    }

    onepassword = {
      source = "1Password/onepassword"
    }

    random = {
      source = "hashicorp/random"
    }

    resend = {
      source = "y0n0zawa/resend"
    }

    tailscale = {
      source = "tailscale/tailscale"
    }

    talos = {
      source = "siderolabs/talos"
    }

    truenas = {
      source = "PjSalty/truenas"
    }

    unifi = {
      source = "ubiquiti-community/unifi"
    }
  }
}
