terraform {
  required_version = ">= 1.10"

  required_providers {
    age = {
      source = "clementblaise/age"
    }
    b2 = {
      source = "backblaze/b2"
    }
    bitwarden = {
      source = "maxlaverse/bitwarden"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
    deepmerge = {
      source = "isometry/deepmerge"
    }
    github = {
      source = "integrations/github"
    }
    htpasswd = {
      source = "loafoe/htpasswd"
    }
    incus = {
      source = "lxc/incus"
    }
    oci = {
      source = "oracle/oci"
    }
    random = {
      source = "hashicorp/random"
    }
    restapi = {
      source = "mastercard/restapi"
    }
    shell = {
      source = "linyinfeng/shell"
    }
    tailscale = {
      source = "tailscale/tailscale"
    }
    talos = {
      source = "siderolabs/talos"
    }
    unifi = {
      source = "ubiquiti-community/unifi"
    }
  }
}
