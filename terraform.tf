terraform {
  required_version = ">= 1.12.5, < 2.0.0"

  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = ">= 3.3.1, < 4.0.0"
    }

    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.11.0, < 0.12.0"
    }

    truenas = {
      source  = "PjSalty/truenas"
      version = ">= 2.4.1, < 3.0.0"
    }
  }
}
