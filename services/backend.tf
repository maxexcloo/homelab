terraform {
  cloud {
    hostname     = "app.terraform.io"
    organization = "excloo"

    workspaces {
      name = "homelab-services"
    }
  }
}
